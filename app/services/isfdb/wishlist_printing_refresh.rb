module Isfdb
  # Refreshes WishlistPrinting — every physical ISFDB printing of each
  # wishlist book, looked up via /isbn/{isbn}/editions on the ISBN the
  # item was wishlisted under (no Work needed: wishlist items are
  # deliberately not catalogued). Same shape as SiblingIsbnRefresh: a
  # thread pool for the adapter calls, persisted afterwards, bounded by a
  # wall-clock deadline; whatever a truncated run didn't reach is still
  # stale next time. See docs/BARGAIN_HUNTING.md.
  #
  # Rows are upserted by (wishlist_item, isfdb_pub_id) rather than
  # replaced, so a printing keeps its id across refreshes for anything
  # that points at it.
  class WishlistPrintingRefresh
    STALE_AFTER = 7.days
    POOL_SIZE = 6
    DEADLINE = 15.minutes
    # ISFDB bindings that aren't a physical book: ebook, "audio CD",
    # "digital audio download", "audio MP3 CD", … ("dos" — dos-à-dos, the
    # Ace Doubles — is physical and stays.)
    NON_PHYSICAL = /\Aebook\z|audio/i
    UPDATED_COLUMNS = %i[isbn13 isbn10 publisher binding publish_date cover_artist cover_url updated_at].freeze

    Result = Struct.new(:items, :stale, :refreshed, :truncated, keyword_init: true) do
      def to_s = "items=#{items} stale=#{stale} refreshed=#{refreshed}#{' TRUNCATED' if truncated}"
    end

    def self.run(**) = new(**).run

    def initialize(client: Client.new, max_age: STALE_AFTER, pool_size: POOL_SIZE, deadline: DEADLINE)
      @client = client
      @max_age = max_age
      @pool_size = pool_size
      @deadline = deadline
    end

    def run
      items = WishlistItem.all.to_a
      stale = items.select { |i| i.printings_refreshed_at.nil? || i.printings_refreshed_at < @max_age.ago }

      fetched = Concurrent::Hash.new
      pool = Concurrent::FixedThreadPool.new(@pool_size)
      stale.each do |item|
        isbns = item.source_isbns
        pool.post do
          editions = isbns.empty? ? [] : lookup(item, isbns)
          fetched[item.id] = editions unless editions.nil?
        end
      end
      pool.shutdown
      truncated = !pool.wait_for_termination(@deadline)
      pool.kill if truncated

      items_by_id = stale.index_by(&:id)
      fetched.each { |id, editions| persist(items_by_id.fetch(id), editions) }

      Rails.logger.warn("wishlist printing refresh truncated: #{stale.size - fetched.size} items unprocessed") if truncated
      Result.new(items: items.size, stale: stale.size, refreshed: fetched.size, truncated:)
    end

    private

    # Adapter edition hashes, [] when ISFDB doesn't know the book, nil on
    # an adapter failure (left stale, retried next run).
    def lookup(item, isbns)
      isbns.each do |isbn|
        editions = @client.lookup_editions(isbn)
        return editions if editions.any?
      end
      []
    rescue StandardError => e
      Rails.logger.warn("wishlist printing refresh: item ##{item.id} — #{e.class}: #{e.message}")
      nil
    end

    def persist(item, editions)
      now = Time.current
      rows = editions.filter_map { |ed| row(item, ed, now) }.uniq { |r| r[:isfdb_pub_id] }

      WishlistPrinting.transaction do
        if rows.any?
          WishlistPrinting.upsert_all(rows, unique_by: [ :wishlist_item_id, :isfdb_pub_id ],
                                            update_only: UPDATED_COLUMNS, record_timestamps: false)
        end
        item.wishlist_printings.where.not(isfdb_pub_id: rows.map { |r| r[:isfdb_pub_id] }).delete_all
        item.update_columns(printings_refreshed_at: now)
      end
    end

    def row(item, ed, now)
      return if ed["_isfdb_pub_id"].blank? || ed["binding"].blank? || ed["binding"].match?(NON_PHYSICAL)

      {
        wishlist_item_id: item.id,
        isfdb_pub_id: ed["_isfdb_pub_id"],
        isbn13: ed["isbn_13"].presence,
        isbn10: ed["isbn_10"].presence,
        publisher: publisher(ed["publisher"]),
        binding: ed["binding"],
        publish_date: ed["publish_date"].presence,
        cover_artist: Array(ed["cover_artists"]).join(", ").presence,
        cover_url: ed["cover_url"].to_s.split("|").first.presence, # ISFDB sometimes holds "url|url"
        created_at: now,
        updated_at: now
      }
    end

    # The authority file's preferred name where there is one, so the same
    # publisher compares equal across printings and, later, listings.
    def publisher(name)
      name.presence && (Authority.resolve("publisher", name) || name)
    end
  end
end

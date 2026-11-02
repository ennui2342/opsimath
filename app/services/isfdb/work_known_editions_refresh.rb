module Isfdb
  # Fills ProviderEdition with the editions ISFDB knows for each catalogued
  # work, and records the work's ISFDB title id as a WorkIdentifier
  # (docs/CATALOG.md, "Architecture review"). Replaces SiblingIsbnRefresh,
  # which cached only those editions' ISBNs, and only for owned works.
  #
  # Looked up via /isbn/{isbn}/editions on the work's own ISBNs — every
  # printing's ISBN resolves to the same ISFDB title, so the first that
  # returns anything wins (Isfdb::WorkEditions). All bindings are kept,
  # ebooks included: the shop app's ISBN index has always used them.
  #
  # Same shape and cadence as before: a thread pool for the adapter calls,
  # persisted afterwards, bounded by a wall-clock deadline; a work is
  # re-queried when it's never been, after max_age, or when its own ISBNs
  # change. An adapter failure leaves the work stale for the next run.
  # Rows are upserted by (work, provider, provider_id) so an edition keeps
  # its id across refreshes.
  class WorkKnownEditionsRefresh
    PROVIDER = "isfdb".freeze
    STALE_AFTER = 7.days
    POOL_SIZE = 6
    DEADLINE = 15.minutes
    UPDATED_COLUMNS = %i[isbn13 isbn10 title publisher binding publish_date language page_count cover_url cover_artist updated_at].freeze

    Result = Struct.new(:works, :stale, :refreshed, :truncated, keyword_init: true) do
      def to_s = "works=#{works} stale=#{stale} refreshed=#{refreshed}#{' TRUNCATED' if truncated}"
    end

    def self.run(**) = new(**).run

    def initialize(client: Client.new, max_age: STALE_AFTER, pool_size: POOL_SIZE, deadline: DEADLINE)
      @client = client
      @max_age = max_age
      @pool_size = pool_size
      @deadline = deadline
    end

    def run
      works = Work.includes(editions: :edition_identifiers).to_a
      isbns_by_id = works.to_h { |w| [ w.id, source_isbns(w) ] }
      stale = works.select do |w|
        w.known_editions_refreshed_at.nil? || w.known_editions_refreshed_at < @max_age.ago ||
          w.known_editions_queried_isbns.sort != isbns_by_id[w.id].sort
      end

      fetched = Concurrent::Hash.new
      pool = Concurrent::FixedThreadPool.new(@pool_size)
      stale.each do |work|
        isbns = isbns_by_id[work.id]
        pool.post do
          editions = isbns.empty? ? [] : lookup(work, isbns)
          fetched[work.id] = editions unless editions.nil?
        end
      end
      pool.shutdown
      truncated = !pool.wait_for_termination(@deadline)
      pool.kill if truncated

      works_by_id = stale.index_by(&:id)
      fetched.each { |id, editions| persist(works_by_id.fetch(id), editions, isbns_by_id.fetch(id)) }

      Rails.logger.warn("known editions refresh truncated: #{stale.size - fetched.size} works unprocessed") if truncated
      Result.new(works: works.size, stale: stale.size, refreshed: fetched.size, truncated:)
    end

    private

    # ISBN-13 first (what the adapter's own examples use), then ISBN-10.
    def source_isbns(work)
      work.editions.flat_map(&:edition_identifiers)
          .select { |i| i.id_type == "isbn13" || i.id_type == "isbn10" }
          .sort_by { |i| i.id_type == "isbn13" ? 0 : 1 }
          .map(&:value).uniq
    end

    def lookup(work, isbns)
      WorkEditions.for(work, client: @client, isbns:)
    rescue StandardError => e
      Rails.logger.warn("known editions refresh: work ##{work.id} — #{e.class}: #{e.message}")
      nil
    end

    def persist(work, editions, isbns)
      now = Time.current
      rows = editions.filter_map { |ed| row(work, ed, now) }.uniq { |r| r[:provider_id] }

      ProviderEdition.transaction do
        if rows.any?
          ProviderEdition.upsert_all(rows, unique_by: [ :work_id, :provider, :provider_id ],
                                           update_only: UPDATED_COLUMNS, record_timestamps: false)
        end
        work.provider_editions.where(provider: PROVIDER).where.not(provider_id: rows.map { |r| r[:provider_id] }).delete_all
        record_title_ids(work, editions, isbns)
        work.update_columns(known_editions_refreshed_at: now, known_editions_queried_isbns: isbns)
      end
    end

    def row(work, ed, now)
      return if ed["_isfdb_pub_id"].blank?

      {
        work_id: work.id, provider: PROVIDER, provider_id: ed["_isfdb_pub_id"].to_s,
        isbn13: ed["isbn_13"].presence, isbn10: ed["isbn_10"].presence,
        title: ed["title"].presence, publisher: ed["publisher"].presence, binding: ed["binding"].presence,
        publish_date: ed["publish_date"].presence, language: ed["language"].presence, page_count: ed["page_count"],
        cover_url: ed["cover_url"].to_s.split("|").first.presence, # ISFDB sometimes holds "url|url"
        cover_artist: Array(ed["cover_artists"]).join(", ").presence,
        created_at: now, updated_at: now
      }
    end

    # The work's own ISFDB title — taken only from the publications with one
    # of the work's own ISBNs. The edition list also holds every omnibus or
    # collection containing the work, each reporting its own main title
    # (four Silverberg novels would otherwise share one omnibus's id).
    def record_title_ids(work, editions, isbns)
      own = isbns.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact
      editions.select { |ed| own.include?(ed["isbn_13"].presence || (ed["isbn_10"].presence && Isbn.to_13(ed["isbn_10"]))) }
              .filter_map { |ed| ed["_isfdb_title_id"].presence&.to_s }.uniq.each do |title_id|
        work.work_identifiers.find_or_create_by!(id_type: "isfdb_title", value: title_id) { |i| i.source = "isbn_lookup" }
      end
    end
  end
end

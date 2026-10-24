module Isfdb
  # Caches each wishlist item's author as living or dead (from ISFDB's
  # author record) for CollectingProfile's buy-new rule: a book never
  # published in A-format by a living author is bought new, not hunted on
  # eBay (docs/BARGAIN_HUNTING.md).
  #
  # The author is matched by exact name (case and punctuation folded)
  # among ISFDB's canonical names; no match leaves the item :unknown,
  # which the rule treats as living. Several matches are variant-spelling
  # records for one person ("Ursula K. Le Guin" #37 and "Ursula K.
  # LeGuin" #229311): the oldest (lowest id) is the main record, the one
  # carrying the dates. The adapter's search
  # is a plain substring match, so it's given the surname (the last
  # plain-ASCII word, skipping Jr./Sr.) and the full comparison is done
  # here: Goodreads writes "J.G. Ballard" where ISFDB has
  # "J. G. Ballard". A common surname can overflow the result limit
  # ("Taylor"), so the full name is tried next. A non-ASCII query
  # ("Stanisław") makes the adapter fail outright, so it's never sent. Death dates rarely
  # change, so an item is re-checked monthly. Each distinct name is looked
  # up once per run.
  class WishlistAuthorRefresh
    STALE_AFTER = 30.days
    POOL_SIZE = 4
    DEADLINE = 15.minutes

    Result = Struct.new(:items, :stale, :authors, :checked, :truncated, keyword_init: true) do
      def to_s = "items=#{items} stale=#{stale} authors=#{authors} checked=#{checked}#{' TRUNCATED' if truncated}"
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
      stale = items.select { |i| i.author_name.present? && (i.author_checked_at.nil? || i.author_checked_at < @max_age.ago) }
      names = stale.map(&:author_name).uniq

      found = Concurrent::Hash.new
      pool = Concurrent::FixedThreadPool.new(@pool_size)
      names.each do |name|
        pool.post do
          status = lookup(name)
          found[name] = status if status
        end
      end
      pool.shutdown
      truncated = !pool.wait_for_termination(@deadline)
      pool.kill if truncated

      now = Time.current
      checked = stale.select { |i| found.key?(i.author_name) }
      checked.each do |item|
        author_id, died = found[item.author_name]
        item.update_columns(author_isfdb_id: author_id, author_died_date: died, author_checked_at: now)
      end

      Rails.logger.warn("wishlist author refresh truncated: #{names.size - found.size} authors unprocessed") if truncated
      Result.new(items: items.size, stale: stale.size, authors: names.size, checked: checked.size, truncated:)
    end

    private

    # [isfdb_author_id, died_date] — [nil, nil] when the name matches no
    # ISFDB author; nil on an adapter failure
    # (left stale, retried next run).
    def lookup(name)
      main = search_terms(name).lazy.filter_map do |term|
        @client.search_authors(term)
               .select { |a| Authority.normalize(a["name"]) == Authority.normalize(name) }
               .min_by { |a| a["external_id"].to_i }
      end.first
      return [ nil, nil ] unless main

      author = @client.author(main["external_id"])
      author ? [ author["external_id"].to_i, author["died_date"].presence ] : [ nil, nil ]
    rescue StandardError => e
      Rails.logger.warn("wishlist author refresh: #{name} — #{e.class}: #{e.message}")
      nil
    end

    SUFFIXES = %w[jr sr ii iii].freeze

    def search_terms(name)
      words = name.split.map { |word| word.delete(".,") }.grep(/\A[A-Za-z'-]+\z/)
      surname = words.reject { |word| SUFFIXES.include?(word.downcase) }.last
      [ surname, (name if name.ascii_only?) ].compact.uniq
    end
  end
end

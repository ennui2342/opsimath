module Isfdb
  # Records each author as living or dead (from ISFDB's author record),
  # and their ISFDB id, on the Contributor — wanted books' authors first — CollectingProfile's buy-new rule:
  # a book never published in A-format by a living author is bought new,
  # not hunted on eBay (docs/BARGAIN_HUNTING.md). Was WishlistAuthorRefresh,
  # which kept the answer on each wishlist item; life dates belong to the
  # person (docs/CATALOG.md, "Architecture review").
  #
  # The author is matched by exact name (case and punctuation folded)
  # among ISFDB's canonical names; no match leaves the contributor
  # :unknown, which the rule treats as living. Several matches are
  # variant-spelling records for one person ("Ursula K. Le Guin" #37 and
  # "Ursula K. LeGuin" #229311): the oldest (lowest id) is the main record,
  # the one carrying the dates. The adapter's search is a plain substring
  # match, so it's given the surname (the last plain-ASCII word, skipping
  # Jr./Sr.) and the full comparison is done here: Goodreads writes "J.G.
  # Ballard" where ISFDB has "J. G. Ballard". A common surname can overflow
  # the result limit ("Taylor"), so the full name is tried next. A
  # non-ASCII query ("Stanisław") makes the adapter fail outright, so it's
  # never sent. Death dates rarely change, so a contributor is re-checked
  # monthly.
  class ContributorLifeRefresh
    STALE_AFTER = 30.days
    POOL_SIZE = 4
    DEADLINE = 15.minutes

    Result = Struct.new(:authors, :stale, :checked, :truncated, keyword_init: true) do
      def to_s = "authors=#{authors} stale=#{stale} checked=#{checked}#{' TRUNCATED' if truncated}"
    end

    def self.run(**) = new(**).run

    def initialize(client: Client.new, max_age: STALE_AFTER, pool_size: POOL_SIZE, deadline: DEADLINE)
      @client = client
      @max_age = max_age
      @pool_size = pool_size
      @deadline = deadline
    end

    # One contributor now (their author page): linked and dated if ISFDB
    # has them. -> the contributor, reloaded.
    def self.link(contributor, client: Client.new)
      found = new(client:).send(:lookup, contributor.name) or return contributor
      author_id, died = found
      ids = author_id ? contributor.external_ids.merge("isfdb" => author_id.to_s) : contributor.external_ids
      contributor.update_columns(died_date: died, life_checked_at: Time.current, external_ids: ids)
      contributor
    end

    # Wanted books' authors first (the buy-new rule needs them), then every
    # other author in the catalogue — linked to ISFDB for their page.
    def run
      wanted = Contributor.where(id: WorkContributor.where(role: "author", work_id: Want.select(:work_id)).select(:contributor_id)).to_a
      authors = (wanted + Contributor.where(id: WorkContributor.where(role: "author").select(:contributor_id)).order(:id).to_a).uniq
      stale = authors.select { |c| c.life_checked_at.nil? || c.life_checked_at < @max_age.ago }

      found = Concurrent::Hash.new
      pool = Concurrent::FixedThreadPool.new(@pool_size)
      stale.each do |contributor|
        pool.post do
          status = lookup(contributor.name)
          found[contributor.id] = status if status
        end
      end
      pool.shutdown
      truncated = !pool.wait_for_termination(@deadline)
      pool.kill if truncated

      now = Time.current
      stale.select { |c| found.key?(c.id) }.each do |contributor|
        author_id, died = found[contributor.id]
        ids = author_id ? contributor.external_ids.merge("isfdb" => author_id.to_s) : contributor.external_ids
        contributor.update_columns(died_date: died, life_checked_at: now, external_ids: ids)
      end

      Rails.logger.warn("contributor life refresh truncated: #{stale.size - found.size} authors unprocessed") if truncated
      Result.new(authors: authors.size, stale: stale.size, checked: found.size, truncated:)
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

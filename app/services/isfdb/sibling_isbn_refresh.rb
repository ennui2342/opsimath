module Isfdb
  # Refreshes WorkSiblingIsbns — the cache Mobile::SnapshotBuilder reads
  # instead of fanning ~2,000 live ISFDB lookups on every snapshot build.
  # Off the critical path, so it can take its time; a wall-clock deadline
  # still bounds a pathological adapter and the next run picks up whatever
  # this one didn't reach (and logs that it was truncated).
  #
  # Re-queries a work when its cache row is missing, older than `max_age`,
  # or when the work's own ISBNs have changed since it was queried.
  class SiblingIsbnRefresh
    STALE_AFTER = 7.days
    POOL_SIZE = 6
    DEADLINE = 15.minutes

    Result = Struct.new(:owned, :stale, :refreshed, :truncated, keyword_init: true) do
      def to_s = "owned=#{owned} stale=#{stale} refreshed=#{refreshed}#{' TRUNCATED' if truncated}"
    end

    def self.run(**) = new(**).run

    def initialize(client: Client.new, max_age: STALE_AFTER, pool_size: POOL_SIZE, deadline: DEADLINE)
      @client = client
      @max_age = max_age
      @pool_size = pool_size
      @deadline = deadline
    end

    def run
      works = owned_works
      isbns_by_id = works.to_h { |w| [ w.id, source_isbns(w) ] }
      cached = WorkSiblingIsbns.where(work_id: works.map(&:id)).index_by(&:work_id)
      stale = works.select do |w|
        row = cached[w.id]
        row.nil? || row.stale?(isbns_by_id[w.id], max_age: @max_age)
      end

      rows = Concurrent::Array.new
      pool = Concurrent::FixedThreadPool.new(@pool_size)
      stale.each do |work|
        isbns = isbns_by_id[work.id]
        pool.post do
          siblings = isbns.empty? ? [] : sibling_isbn13s(work, isbns)
          rows << [ work.id, isbns, siblings ] unless siblings.nil?
        end
      end
      pool.shutdown
      truncated = !pool.wait_for_termination(@deadline)
      pool.kill if truncated

      persist(rows)
      prune(works.map(&:id))

      Rails.logger.warn("sibling ISBN refresh truncated: #{stale.size - rows.size} works unprocessed") if truncated
      Result.new(owned: works.size, stale: stale.size, refreshed: rows.size, truncated:)
    end

    private

    def owned_works
      owned_editions = Copy.where(disposition: "owned").distinct.pluck(:edition_id)
      work_ids = EditionContent.where(edition_id: owned_editions).distinct.pluck(:work_id)
      Work.where(id: work_ids).includes(editions: :edition_identifiers).to_a
    end

    def source_isbns(work)
      work.editions
          .flat_map(&:edition_identifiers)
          .select { |i| i.id_type == "isbn13" || i.id_type == "isbn10" }
          .sort_by { |i| i.id_type == "isbn13" ? 0 : 1 }
          .map(&:value)
          .uniq
    end

    def sibling_isbn13s(work, isbns)
      WorkEditions.for(work, client: @client, isbns:).filter_map do |ed|
        ed["isbn_13"].presence || (ed["isbn_10"].presence && Isbn.to_13(ed["isbn_10"]))
      end.uniq
    rescue StandardError => e
      Rails.logger.warn("sibling ISBN refresh: work ##{work.id} — #{e.class}: #{e.message}")
      nil
    end

    def persist(rows)
      return if rows.empty?

      now = Time.current
      WorkSiblingIsbns.upsert_all(
        rows.map { |work_id, isbns, siblings| { work_id:, isbn13s: siblings, queried_isbns: isbns, refreshed_at: now } },
        unique_by: :work_id
      )
    end

    def prune(current_ids)
      WorkSiblingIsbns.where.not(work_id: current_ids).delete_all
    end
  end
end

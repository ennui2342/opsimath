module Isfdb
  # Each ISFDB-linked book's main title and variant titles (isfdb-adapter
  # /titles/:id, by its isfdb_title identifiers), kept on the Work for
  # TitleCleanup. Fetched when missing or a month old; nightly, before the
  # title cleanup.
  class MainTitles
    STALE_AFTER = 30.days
    POOL_SIZE = 4
    DEADLINE = 10.minutes

    def self.run(works = nil, client: Client.new) = new(client:).run(works)

    def initialize(client:)
      @client = client
    end

    # -> number of books updated
    def run(works = nil)
      works ||= Work.where(id: WorkIdentifier.where(id_type: "isfdb_title").select(:work_id))
                    .where("isfdb_titles_checked_at IS NULL OR isfdb_titles_checked_at < ?", STALE_AFTER.ago)
      ids = WorkIdentifier.where(id_type: "isfdb_title", work_id: works.select(:id)).order(:id).pluck(:work_id, :value).group_by(&:first)
      found = Concurrent::Hash.new
      started = Time.current
      pool = Concurrent::FixedThreadPool.new(POOL_SIZE)
      ids.each do |work_id, rows|
        pool.post do
          next if Time.current - started > DEADLINE

          found[work_id] = rows.map(&:last).filter_map { |id| @client.title(id) }
        rescue StandardError => e
          Rails.logger.warn("ISFDB main titles: work ##{work_id} — #{e.class}: #{e.message}")
        end
      end
      pool.shutdown
      pool.kill unless pool.wait_for_termination(DEADLINE + 1.minute)

      now = Time.current
      found.each do |work_id, records|
        next if records.empty?

        main = records.first["main"]["title"]
        variants = records.flat_map { |r| [ r["main"]["title"], r["title"], *r["variants"].map { |v| v["title"] } ] }.uniq - [ main ]
        Work.where(id: work_id).update_all(isfdb_main_title: main, isfdb_variant_titles: variants, isfdb_titles_checked_at: now)
      end
      found.size
    end
  end
end

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
      titles = Work.where(id: found.keys).pluck(:id, :title).to_h
      found.each do |work_id, records|
        next if records.empty?

        main, variants = self.class.english_titles(records, current: titles[work_id])
        Work.where(id: work_id).update_all(isfdb_main_title: main, isfdb_variant_titles: variants, isfdb_titles_checked_at: now)
      end
      found.size
    end

    ENGLISH = %w[eng en].freeze

    # [main title, its other English titles] from /titles/:id records. The
    # main title in English: ISFDB's own when it's English (or says no
    # language); for a translation, ISFDB's main title is the original
    # (Пикник на обочине), so the English variant matching the book's
    # current title (Roadside Picnic), else the English variant sharing
    # most words with it, else the first. HTML entities decoded (ISFDB
    # stores non-Latin titles as &#…;).
    def self.english_titles(records, current:)
      decode = ->(t) { CGI.unescapeHTML(t.to_s) }
      english = ->(lang) { lang.blank? || ENGLISH.include?(lang.to_s.downcase) }
      first = records.first
      variants = records.flat_map { |r| r["variants"] }.uniq { |v| v["id"] }
      english_variants = variants.select { |v| english.(v["language"]) }.map { |v| decode.(v["title"]) }
      main = if english.(first["main"]["language"]) then decode.(first["main"]["title"])
      else
               words = ->(t) { I18n.transliterate(t.to_s).downcase.scan(/[a-z0-9]+/) }
               english_variants.find { |v| words.(v) == words.(current) } ||
                 english_variants.max_by { |v| (words.(v) & words.(current)).size } || decode.(first["main"]["title"])
      end
      [ main, ((english.(first["main"]["language"]) ? [] : [ decode.(first["main"]["title"]) ]) + english_variants).uniq - [ main ] ]
    end
  end
end

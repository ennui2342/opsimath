module Isfdb
  # Each ISFDB-linked book's main title and variant titles (isfdb-adapter
  # /titles/:id, by its isfdb_title identifiers), kept on the Work for
  # TitleCleanup — and, from the main title, the book's literary form,
  # first-publication year and original language (BOOK_FIELDS), which
  # until 2026-11-13 only ever came from the Goodreads import (2,144 of
  # 2,166 linked books said "novel"). ISFDB wins unless Mark set the field
  # himself. Fetched when missing or a month old; nightly, before the
  # title cleanup.
  class MainTitles
    STALE_AFTER = 30.days
    # Fetched before /titles carried type, year and language: fetched again.
    REFETCH_BEFORE = Time.utc(2026, 11, 13, 12)
    BOOK_FIELDS = %w[literary_form original_publication_year original_language].freeze
    # ISFDB title type → Work#literary_form. A standalone novella is a
    # CHAPBOOK in ISFDB.
    FORMS = { "NOVEL" => "novel", "CHAPBOOK" => "novella", "COLLECTION" => "collection", "ANTHOLOGY" => "anthology",
              "NONFICTION" => "nonfiction", "OMNIBUS" => "omnibus", "MAGAZINE" => "periodical" }.freeze
    POOL_SIZE = 4
    DEADLINE = 10.minutes

    def self.run(works = nil, client: Client.new) = new(client:).run(works)

    def initialize(client:)
      @client = client
    end

    # -> number of books updated
    def run(works = nil)
      works ||= Work.where(id: WorkIdentifier.where(id_type: "isfdb_title").select(:work_id))
                    .where("isfdb_titles_checked_at IS NULL OR isfdb_titles_checked_at < ?", [ STALE_AFTER.ago, REFETCH_BEFORE ].max)
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
      Work.where(id: found.keys).find_each do |work|
        records = found[work.id]
        next if records.blank?

        records = self.class.ordered(records, work.title)
        main, variants = self.class.english_titles(records, current: work.title)
        work.update_columns(isfdb_main_title: main, isfdb_variant_titles: variants, isfdb_titles_checked_at: now)
        self.class.apply_book_fields(work, records.first["main"])
      end
      found.size
    end

    CONTAINERS = %w[OMNIBUS COLLECTION ANTHOLOGY].freeze

    # A book linked to several ISFDB titles (170 are — often by an ISBN that
    # led to something it contains or is contained in), the one that is
    # this book first: a record whose main or variant title is the book's
    # title; then a real book over a chapbook (The Midwich Cuckoos: the
    # novel, not the schools chapbook); then the container over a work in
    # it (Revolt in 2100: the collection, not "If This Goes On—" — a
    # collection's printings are its contents' too). Among titles still level — two ISFDB titles of one name (a collection
    # reissued with other contents) — the one holding a printing Mark has
    # (`own`: title ids, where known), then the earliest (The Caves of
    # Steel: 1954, not 1978). Nothing matching: TitleCleanup calls the
    # book suspect.
    def self.ordered(records, title, own: [])
      fold = ->(t) { I18n.transliterate(CGI.unescapeHTML(t.to_s)).downcase.gsub(/[^a-z0-9]+/, " ").strip.sub(/\A(the|a|an) /, "") }
      mine = fold.(WorkMatcher.plain(title))
      records.each_with_index.sort_by do |r, i|
        names = [ r["main"]["title"], r["title"], *Array(r["variants"]).map { |v| v["title"] } ].map(&fold)
        type = r["main"]["type"].to_s.upcase
        [ names.include?(mine) ? 0 : 1, type == "CHAPBOOK" ? 1 : 0, CONTAINERS.include?(type) ? 0 : 1,
          own.include?(r["id"].to_s) ? 0 : 1, r["main"]["year"] || 9999, i ]
      end.map(&:first)
    end

    # A main title record's {field => value} for the book (nil values left out).
    def self.book_fields(main)
      { "literary_form" => FORMS[main["type"].to_s.upcase],
        "original_publication_year" => main["year"].presence&.to_i,
        "original_language" => main["language"].presence }.compact
    end

    # The book's form, year and language from ISFDB — not a field Mark set
    # himself. -> the fields changed.
    def self.apply_book_fields(work, main)
      return [] if TitleCleanup.suspect?(work) # a likely wrong link: take nothing from it

      changes = book_fields(main).reject { |field, value| work.field_sources[field] == "manual" || work.public_send(field) == value }
      return [] if changes.empty?

      work.update!(changes.merge("field_sources" => work.field_sources.merge(changes.keys.index_with { "isfdb" })))
      changes.keys
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

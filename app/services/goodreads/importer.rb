require "csv"

module Goodreads
  # Phase 1 bulk CSV import — see docs/INTEGRATIONS.md. One-time (or
  # re-runnable) import of a Goodreads library export.
  #
  # Re-run safety: a row is skipped once its `Book Id` already exists as a
  # `goodreads`-type EditionIdentifier. This makes a full clean re-run a
  # no-op. It does NOT guarantee full idempotency for a re-run against a
  # CSV that's been hand-edited to add new read events to an
  # already-partially-imported book — that's a real, accepted limitation
  # for a "one-time (or re-runnable)" bulk import, not a promise this
  # makes.
  #
  # Work-grouping, not row-by-row: rows are grouped by (normalized title,
  # author) before processing, and Reading creation for the read/
  # did-not-finish shelves is derived from the *union* of dated read
  # events across the whole group, not per-row. This was found necessary,
  # not just tidier — confirmed directly against the real export that of
  # 7 real (title, author) pairs with two independent 'read'-shelf rows
  # (Goodreads catalog churn: an edition got re-added/split, leaving an
  # empty husk entry with no rating/date behind), the signal-bearing row
  # is NOT reliably the first one encountered in the file (2 of the 7 have
  # the empty row first). A naive row-by-row "first row wins" approach
  # would have misfiled genuine read data as an ambiguous duplicate
  # roughly a third of the time, purely as an artifact of file order.
  class Importer
    Counts = Struct.new(:imported_rows, :skipped_rows, :wishlisted, keyword_init: true) do
      def to_s
        "imported_rows=#{imported_rows} skipped_rows=#{skipped_rows} wishlisted=#{wishlisted}"
      end
    end

    READ_SHELVES = %w[read did-not-finish].freeze

    def self.import(path)
      new(path).import
    end

    def initialize(path)
      @path = path
    end

    def import
      rows = CSV.read(@path, headers: true)
      wishlist_rows, catalog_rows = rows.partition { |row| row["Exclusive Shelf"].to_s.strip == "wishlist" }

      counts = Counts.new(imported_rows: 0, skipped_rows: 0, wishlisted: 0)

      wishlist_rows.each { |row| import_wishlist_row(row, counts) }

      catalog_rows.group_by { |row| work_key(row) }.each_value do |group_rows|
        import_work_group(group_rows, counts)
      end

      counts
    end

    private

    def work_key(row)
      info = RowParser.series_info(row["Title"])
      author = RowParser.clean_name(row["Author"])
      [ info.title.downcase, author&.downcase ]
    end

    # Per docs/INTEGRATIONS.md: a wishlist-shelf row does not create a
    # Work/Edition/Copy at all — only this separate, lightweight list.
    def import_wishlist_row(row, counts)
      book_id = row["Book Id"].to_s.strip
      if WishlistItem.where("external_ids ->> 'goodreads' = ?", book_id).exists?
        counts.skipped_rows += 1
        return
      end

      info = RowParser.series_info(row["Title"])
      external_ids = { "goodreads" => book_id }
      if (isbn13 = RowParser.clean_isbn(row["ISBN13"]))
        external_ids["isbn13"] = isbn13
      end
      if (isbn10 = RowParser.clean_isbn(row["ISBN"]))
        external_ids["isbn10"] = isbn10
      end

      series = info.series_name && Series.where("lower(name) = ?", info.series_name.downcase).first

      WishlistItem.create!(
        title: info.title,
        author_name: RowParser.clean_name(row["Author"]),
        series: series,
        external_ids: external_ids
      )
      counts.wishlisted += 1
    end

    def import_work_group(group_rows, counts)
      work = find_or_create_work(group_rows.first)
      update_literary_form(work, group_rows)
      fresh = []

      group_rows.each do |row|
        book_id = row["Book Id"].to_s.strip
        if EditionIdentifier.exists?(id_type: "goodreads", value: book_id)
          counts.skipped_rows += 1
          next
        end

        link_series(work, row)
        link_contributors(work, row)
        link_shelves(work, row)

        edition = create_edition(row, book_id)
        EditionContent.find_or_create_by!(edition: edition, work: work)

        shelf = row["Exclusive Shelf"].to_s.strip
        create_copies(edition, row)
        open_current_reading(work, edition, row) if shelf == "currently-reading"

        fresh << { row: row, edition: edition }
        counts.imported_rows += 1
      end

      # Runs after link_shelves for the whole group, not before: a real
      # nonfiction topic match (e.g. "SPQR: A History of Ancient Rome" ->
      # Subject "History") must win over the structural "Fiction" default
      # — a Work can't honestly be both. Only applied when nothing more
      # specific matched.
      ensure_fiction_subject(work)

      create_readings_for_group(work, fresh)
    end

    def find_or_create_work(row)
      info = RowParser.series_info(row["Title"])
      author_name = RowParser.clean_name(row["Author"])

      existing = Work.joins(work_contributors: :contributor)
                      .where("lower(works.title) = ?", info.title.downcase)
                      .where(work_contributors: { role: "author" })
                      .where("lower(contributors.name) = ?", author_name.to_s.downcase)
                      .first
      return existing if existing

      # literary_form defaults to "novel" — update_literary_form upgrades
      # this right after creation when a group row's Bookshelves gives a
      # real signal (anthology/collection/essay); otherwise hand-correct
      # per PHILOSOPHY.md principle 6.
      Work.create!(
        title: info.title,
        literary_form: "novel",
        original_publication_year: row["Original Publication Year"].presence&.to_i
      )
    end

    # Only overrides the "novel" default, never a value already set by a
    # prior import or a manual correction — "novel" is treated as the
    # implicit unset/default sentinel for imported Works specifically,
    # not as a real confirmed classification to protect.
    def update_literary_form(work, group_rows)
      return unless work.literary_form == "novel"

      literary_form = group_rows.filter_map { |row| RowParser.literary_form_from_shelves(row["Bookshelves"]) }.first
      work.update!(literary_form: literary_form) if literary_form
    end

    # Every fiction Work gets exactly one shared "Fiction" Subject row —
    # not classified further under Subject, the same way a library
    # wouldn't Dewey-classify a novel beyond "this is fiction" (most
    # public libraries don't apply Dewey to fiction at all, shelving it
    # separately by author). "nonfiction"/"essay" are the only
    # literary_form values that are genuinely non-fiction; those Works
    # get their real Subject from link_shelves instead, never "Fiction".
    #
    # Only applied when the Work has no other Subject already — Goodreads
    # gives no reliable fiction/nonfiction signal for the many books that
    # default to literary_form "novel" without ever being confirmed as
    # fiction (the same reason literary_form itself isn't inferred from a
    # subject tag), so a book that already matched a real Subject (e.g.
    # "History") is trusted over the structural default: it can't
    # honestly be both. A genuinely nonfiction book with *no* recognized
    # subject tag at all will still default to "Fiction" here — a real,
    # bounded gap (Goodreads gives no better signal), hand-correct per
    # PHILOSOPHY.md principle 6.
    FICTION_LITERARY_FORMS = %w[novel novella short_story collection anthology].freeze

    def ensure_fiction_subject(work)
      return unless FICTION_LITERARY_FORMS.include?(work.literary_form)
      return if work.subjects.any?

      fiction = Subject.find_by!(name: "Fiction")
      WorkSubject.find_or_create_by!(work: work, subject: fiction)
    end

    def link_series(work, row)
      info = RowParser.series_info(row["Title"])
      return unless info.series_name

      series = Series.where("lower(name) = ?", info.series_name.downcase).first
      series ||= Series.create!(name: info.series_name)
      WorkSeries.find_or_create_by!(work: work, series: series) do |ws|
        ws.position = info.position
      end
    end

    # Only the primary author has "Author l-f" (sort_name) data available
    # from the CSV — Additional Authors is a raw comma-separated list with
    # no l-f equivalent, confirmed by direct inspection of the real export.
    def link_contributors(work, row)
      primary = RowParser.clean_name(row["Author"])
      sort_names = { primary => RowParser.clean_name(row["Author l-f"]) }
      names = ([ primary ] + RowParser.additional_authors(row["Additional Authors"])).compact.uniq

      names.each_with_index do |name, index|
        contributor = Contributor.find_or_create_by!(name: name)
        if sort_names[name] && contributor.sort_name.blank?
          contributor.update!(sort_name: sort_names[name])
        end
        WorkContributor.find_or_create_by!(work: work, contributor: contributor, role: "author") do |wc|
          wc.display_order = index
        end
      end
    end

    # Bookshelves labels matched (via RowParser::GENRE_ALIASES, then a
    # direct case-insensitive name match) against the Thema-seeded Genre
    # rows (db/seeds.rb) become a WorkGenre; failing that, matched (via
    # RowParser::SUBJECT_ALIASES) against the seeded Subject rows become
    # a WorkSubject; everything else becomes a Tag — this is the
    # expected, correct outcome for the deep SF-critical/personal labels
    # (see DATA_MODEL.md's "Genre / Subject / Tag") that neither
    # controlled vocabulary should cover, not a fallback for missing seed
    # data. Two labels are skipped outright rather than classified at
    # all: the structural ones already consumed by update_literary_form
    # (anthology/collection/essays — Work.literary_form already says
    # "anthology", a redundant Tag/Genre/Subject on top would just be
    # noise), and the bare "fiction" label, which is redundant with the
    # single shared "Fiction" Subject every fiction Work gets structurally
    # (see ensure_fiction_subject) rather than from this per-label match.
    SKIPPED_SHELF_LABELS = (RowParser::LITERARY_FORM_SHELF_SIGNALS.keys + %w[fiction]).freeze

    def link_shelves(work, row)
      RowParser.extra_shelves(row["Bookshelves"]).each do |label|
        next if SKIPPED_SHELF_LABELS.include?(label.downcase)

        genre = Genre.find_by("lower(name) = ?", RowParser.genre_lookup_name(label).downcase)
        if genre
          WorkGenre.find_or_create_by!(work: work, genre: genre)
          next
        end

        subject = Subject.find_by("lower(name) = ?", RowParser.subject_lookup_name(label).downcase)
        if subject
          WorkSubject.find_or_create_by!(work: work, subject: subject)
          next
        end

        tag = Tag.find_or_create_by!(name: label)
        WorkTag.find_or_create_by!(work: work, tag: tag)
      end
    end

    def create_edition(row, book_id)
      format, format_detail = RowParser.format_and_detail(row["Binding"])

      edition = Edition.create!(
        format: format,
        format_detail: format_detail,
        publisher: row["Publisher"].presence,
        publish_date: row["Year Published"].presence, # year only — an EDTF string, not a fabricated day/month
        page_count: row["Number of Pages"].presence&.to_i
      )

      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: book_id)
      if (isbn10 = RowParser.clean_isbn(row["ISBN"]))
        EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: isbn10)
      end
      if (isbn13 = RowParser.clean_isbn(row["ISBN13"]))
        EditionIdentifier.create!(edition: edition, id_type: "isbn13", value: isbn13)
      end

      edition
    end

    # "Owned Copies" is confirmed near-unused in the real export (0 for
    # 1140/1140 to-read rows, and all but 12 of 819 read rows) despite
    # Mark's already-confirmed convention that the to-read shelf is where
    # a book becomes an owned copy. Treated as a floor, not a gate: shelf
    # membership itself (any non-wishlist shelf) is the ownership signal,
    # Owned Copies only matters when it's genuinely > 1.
    def create_copies(edition, row)
      count = [ row["Owned Copies"].to_i, 1 ].max
      count.times { Copy.create!(edition: edition, disposition: "owned") }
    end

    def open_current_reading(work, edition, row)
      Reading.create!(
        work: work,
        edition: edition,
        status: "reading",
        date_started: RowParser.parse_date_slash(row["Date Added"])
      )
    end

    def create_readings_for_group(work, fresh)
      read_like = fresh.select { |f| READ_SHELVES.include?(f[:row]["Exclusive Shelf"].to_s.strip) }
      return if read_like.empty?

      dated = read_like.flat_map do |f|
        RowParser.read_events(f[:row]["read_dates"], f[:row]["Date Read"])
                 .select { |event| event.date_started || event.date_finished }
                 .map { |event| { event: event, row: f[:row], edition: f[:edition] } }
      end

      if dated.any?
        dated.sort_by! { |d| d[:event].date_finished || d[:event].date_started }
        dated.each_with_index do |d, index|
          reading = Reading.create!(
            work: work, edition: d[:edition], status: status_for(d[:row]),
            date_started: d[:event].date_started, date_finished: d[:event].date_finished
          )
          apply_rating_review(reading, d[:row]) if index == dated.size - 1
        end
      else
        # Entire group is dateless — one Reading with nil dates, per the
        # doc's ordinary-single-read policy (no annotation, not data
        # loss). Rating/review/notes come from whichever row (if any)
        # actually carries them.
        reading = Reading.create!(work: work, edition: read_like.first[:edition], status: status_for(read_like.first[:row]))
        signal_row = read_like.find { |f| has_signal?(f[:row]) }
        apply_rating_review(reading, signal_row[:row]) if signal_row
      end
    end

    def status_for(row)
      row["Exclusive Shelf"].to_s.strip == "did-not-finish" ? "dnf" : "completed"
    end

    def has_signal?(row)
      RowParser.rating(row["My Rating"]) || row["My Review"].presence || row["Private Notes"].presence
    end

    def apply_rating_review(reading, row)
      rating = RowParser.rating(row["My Rating"])
      private_notes = row["Private Notes"].presence
      reading.update!(rating: rating, private_notes: private_notes) if rating || private_notes

      review_text = row["My Review"].presence
      return unless review_text

      Review.create!(
        work: reading.work, reading: reading, text: review_text, rating: rating,
        status: "published", channels: [ { "channel" => "goodreads" } ]
      )
    end
  end
end

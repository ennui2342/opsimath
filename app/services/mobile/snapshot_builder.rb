require "sqlite3"
require "tempfile"

module Mobile
  # Writes Mobile::ShopView into snapshot.sqlite3 — the file the offline
  # shop-lookup PWA downloads and queries locally (docs/MOBILE.md step 4).
  # Thumbnails travel in the file as BLOBs so there's one thing to fetch.
  class SnapshotBuilder
    Result = Struct.new(:io, :byte_size, :entry_count, :generated_at, keyword_init: true)

    SCHEMA = <<~SQL
      CREATE TABLE entries (
        id              TEXT PRIMARY KEY,
        kind            TEXT NOT NULL,
        title           TEXT NOT NULL,
        subtitle        TEXT,
        authors         TEXT,
        series          TEXT,
        series_position TEXT,
        year            INTEGER,
        owned           INTEGER NOT NULL,
        wishlisted      INTEGER NOT NULL,
        thumb           BLOB,
        isbn10          TEXT,
        isbn13          TEXT,
        goodreads       TEXT,
        search_title    TEXT NOT NULL,
        search_author   TEXT,
        search_series   TEXT
      );
      CREATE TABLE editions (
        id             INTEGER PRIMARY KEY,
        entry_id       TEXT NOT NULL,
        format         TEXT,
        format_detail  TEXT,
        publisher      TEXT,
        year           INTEGER,
        page_count     INTEGER,
        disposition    TEXT,
        cover_artist   TEXT,
        reading_status TEXT,
        isbn10         TEXT,
        isbn13         TEXT,
        isfdb          TEXT,
        goodreads      TEXT,
        thumb          BLOB
      );
      CREATE INDEX idx_editions_entry ON editions (entry_id);
      CREATE TABLE isbn_index (
        isbn13     TEXT NOT NULL,
        entry_id   TEXT NOT NULL,
        edition_id INTEGER
      );
      CREATE INDEX idx_isbn ON isbn_index (isbn13);
      CREATE TABLE wants (
        entry_id     TEXT PRIMARY KEY,
        target_pence INTEGER,
        rule         TEXT
      );
      CREATE TABLE covers (
        entry_id       TEXT NOT NULL,
        cover_id       TEXT NOT NULL,
        summary        TEXT,
        artists        TEXT,
        favourite      INTEGER NOT NULL,
        chosen         INTEGER NOT NULL,
        median_pence   INTEGER,
        listing_count  INTEGER NOT NULL,
        cheapest_pence INTEGER
      );
      CREATE INDEX idx_covers_entry ON covers (entry_id);
      CREATE TABLE cover_isbns (
        isbn13   TEXT NOT NULL,
        entry_id TEXT NOT NULL,
        cover_id TEXT NOT NULL
      );
      CREATE INDEX idx_cover_isbns ON cover_isbns (isbn13);
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
    SQL

    def self.build(version:) = new(version).build

    def initialize(version)
      @version = version
      @generated_at = Time.current
    end

    def build
      view = ShopView.build
      thumbs = load_thumbs(view)
      @related_isbns = load_related_isbns(view)
      file = Tempfile.new([ "mobile-snapshot", ".sqlite3" ])
      file.close

      db = SQLite3::Database.new(file.path)
      begin
        db.execute_batch(SCHEMA)
        db.transaction do
          view.entries.each { |entry| write_entry(db, entry, thumbs) }
          write_meta(db, view.entries.size)
        end
      ensure
        db.close
      end

      io = File.open(file.path, "rb")
      Result.new(io:, byte_size: File.size(file.path), entry_count: view.entries.size, generated_at: @generated_at)
    ensure
      file&.unlink
    end

    private

    def write_entry(db, entry, thumbs)
      db.execute(
        "INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          entry.id, entry.kind, entry.title, entry.subtitle,
          entry.authors.join(", ").presence, entry.series, entry.series_position,
          entry.original_year, bool(entry.owned), bool(entry.wishlisted),
          blob(thumbs[entry.id]), entry.isbn10, entry.isbn13, entry.goodreads,
          norm(entry.title), norm(entry.authors.join(" ")), norm(entry.series)
        ]
      )

      entry.editions.each do |edition|
        db.execute(
          "INSERT INTO editions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
          [
            edition.id, entry.id, edition.format, edition.format_detail, edition.publisher,
            edition.year&.to_i, edition.page_count, edition.disposition,
            edition.cover_artist, edition.reading_status,
            edition.isbn10, edition.isbn13, edition.isfdb, edition.goodreads,
            blob(thumbs["edition:#{edition.id}"])
          ]
        )
      end

      isbn_rows(entry).each { |row| db.execute("INSERT INTO isbn_index VALUES (?,?,?)", row) }
      write_want(db, entry) if entry.want
    end

    # Prices (docs/MOBILE.md, "Prices"): the want's target and rule, each
    # offered cover's eBay going rate, and every ISBN its printings carry.
    def write_want(db, entry)
      want = entry.want
      db.execute("INSERT INTO wants VALUES (?,?,?)", [ entry.id, want.target_pence, want.rule ])
      want.covers.each do |c|
        db.execute("INSERT INTO covers VALUES (?,?,?,?,?,?,?,?,?)",
                   [ entry.id, c.id, c.summary, c.artists.join(", ").presence, bool(c.favourite), bool(c.chosen),
                     c.median_pence, c.listing_count, c.cheapest_pence ])
        c.isbns.each { |i13| db.execute("INSERT INTO cover_isbns VALUES (?,?,?)", [ i13, entry.id, c.id ]) }
      end
    end

    # Every ISBN this entry can be scanned by, folded to ISBN-13. A row
    # with an edition_id points at an edition you have a record of — owned
    # or retired (`replaced`/`sold`/…); the client resolves to the work
    # and marks that edition's card with its disposition. A null
    # edition_id is a wishlist item's own ISBN, or — for a work you own —
    # one of the *other* printings ISFDB knows that you have no edition
    # record for at all ("you own a different edition").
    def isbn_rows(entry)
      seen = Set.new
      rows = entry.editions.filter_map do |edition|
        i13 = edition.isbn13 || (edition.isbn10 && Isbn.to_13(edition.isbn10))
        next unless i13

        seen << i13
        [ i13, entry.id, edition.id ]
      end

      if entry.kind == "wishlist"
        i13 = entry.isbn13 || (entry.isbn10 && Isbn.to_13(entry.isbn10))
        rows << [ i13, entry.id, nil ] if i13
        seen << i13 if i13
      end

      (@related_isbns[entry.id] || []).each do |i13|
        rows << [ i13, entry.id, nil ] unless seen.include?(i13)
      end

      rows
    end

    # {entry_id => [ISBN-13, ...]} for the other printings ISFDB knows of
    # each owned work — read straight from ProviderEdition
    # (KnownEditionsRefresh keeps it current, off the build's
    # critical path). No network here.
    # A wanted book (kind "wishlist") is scannable by every printing its
    # work's known editions carry too, not just the ISBN it was wanted
    # under — a different printing in a shop is still the book you want.
    def load_related_isbns(view)
      work_ids = view.entries.filter_map { |e| e.id.delete_prefix("work:").to_i if e.kind == "work" }
      related = ProviderEdition.isbns_by_work(work_ids).transform_keys { |id| "work:#{id}" }
      want_ids = view.entries.filter_map { |e| e.id.delete_prefix("wishlist:").to_i if e.kind == "wishlist" }
      work_by_want = Want.where(id: want_ids).pluck(:id, :work_id).to_h
      by_work = ProviderEdition.isbns_by_work(work_by_want.values)
      work_by_want.each { |want_id, work_id| related["wishlist:#{want_id}"] = by_work[work_id] if by_work.key?(work_id) }
      related
    end

    def write_meta(db, entry_count)
      {
        version: @version, generated_at: @generated_at.iso8601, entry_count: entry_count
      }.each { |k, v| db.execute("INSERT INTO meta VALUES (?,?)", [ k.to_s, v.to_s ]) }
    end

    # {snapshot key ("edition:<id>" / "wishlist:<id>") => thumb bytes} for
    # the covers ShopView flagged. Bytes come from the MobileThumb cache
    # in one query; a miss falls back to a blob download (slow — that's
    # the whole reason for the cache) and backfills it. A thumb that
    # can't be produced is skipped, not fatal.
    def load_thumbs(view)
      records = thumb_records(view)
      keys = records.transform_values { |record| variant_key(record) }
      cached = MobileThumb.fetch(keys.values.compact.uniq)

      keys.each_with_object({}) do |(snap_key, blob_key), thumbs|
        bytes = (blob_key && cached[blob_key]) || download_and_cache(records[snap_key], blob_key)
        thumbs[snap_key] = bytes if bytes
      end
    end

    def thumb_records(view)
      edition_ids = view.entries.flat_map { |e| e.editions.select(&:has_cover).map(&:id) }
      wishlist_ids = view.entries.select { |e| e.kind == "wishlist" && e.has_cover }
                        .map { |e| e.id.delete_prefix("wishlist:").to_i }

      records = {}
      Edition.where(id: edition_ids).includes(cover_image_attachment: :blob).find_each do |e|
        records["edition:#{e.id}"] = e
      end
      Want.where(id: wishlist_ids).includes(cover_image_attachment: :blob).find_each do |w|
        records["wishlist:#{w.id}"] = w
      end
      records
    end

    # The variant's own blob key — the MobileThumb cache key. For an
    # already-generated variant (preprocessed on attach, warmed by
    # `rake mobile:warm_thumbs`) `.processed` is DB-only, no storage I/O;
    # it's the `.download` in the fallback below that the cache exists to
    # avoid, not this.
    def variant_key(record)
      record.cover_image.variant(:thumb).processed.key
    rescue StandardError => e
      Rails.logger.warn("mobile snapshot: variant key failed for #{record.class}##{record.id} — #{e.message}")
      nil
    end

    def download_and_cache(record, blob_key)
      bytes = record.cover_image.variant(:thumb).processed.download
      MobileThumb.store(blob_key, bytes)
      bytes
    rescue StandardError => e
      Rails.logger.warn("mobile snapshot: :thumb download failed for #{record.class}##{record.id} — #{e.message}")
      nil
    end

    def norm(str)
      return nil if str.blank?

      ActiveSupport::Inflector.transliterate(str).downcase.strip
    end

    def bool(value) = value ? 1 : 0
    def blob(bytes) = bytes && SQLite3::Blob.new(bytes)
  end
end

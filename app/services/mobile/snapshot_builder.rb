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
        search_title    TEXT NOT NULL,
        search_author   TEXT,
        search_series   TEXT
      );
      CREATE TABLE editions (
        id            INTEGER PRIMARY KEY,
        entry_id      TEXT NOT NULL,
        format        TEXT,
        format_detail TEXT,
        publisher     TEXT,
        year          INTEGER,
        isbn10        TEXT,
        isbn13        TEXT,
        isfdb         TEXT,
        goodreads     TEXT,
        thumb         BLOB
      );
      CREATE INDEX idx_editions_entry ON editions (entry_id);
      CREATE TABLE isbn_index (
        isbn13     TEXT NOT NULL,
        entry_id   TEXT NOT NULL,
        edition_id INTEGER
      );
      CREATE INDEX idx_isbn ON isbn_index (isbn13);
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
        "INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          entry.id, entry.kind, entry.title, entry.subtitle,
          entry.authors.join(", ").presence, entry.series, entry.series_position,
          entry.original_year, bool(entry.owned), bool(entry.wishlisted),
          blob(thumbs[entry.id]), entry.isbn10, entry.isbn13,
          norm(entry.title), norm(entry.authors.join(" ")), norm(entry.series)
        ]
      )

      entry.editions.each do |edition|
        db.execute(
          "INSERT INTO editions VALUES (?,?,?,?,?,?,?,?,?,?,?)",
          [
            edition.id, entry.id, edition.format, edition.format_detail, edition.publisher,
            edition.year&.to_i, edition.isbn10, edition.isbn13, edition.isfdb, edition.goodreads,
            blob(thumbs["edition:#{edition.id}"])
          ]
        )
      end

      isbn_rows(entry).each { |row| db.execute("INSERT INTO isbn_index VALUES (?,?,?)", row) }
    end

    # Every ISBN this entry can be scanned by, folded to ISBN-13. Rows
    # with an edition_id are an edition you own; a null edition_id is a
    # wishlist item or — for an owned work — one of the *other* printings
    # ISFDB knows (you own a different edition of that book).
    def isbn_rows(entry)
      owned = Set.new
      rows = entry.editions.filter_map do |edition|
        i13 = edition.isbn13 || (edition.isbn10 && Isbn.to_13(edition.isbn10))
        next unless i13

        owned << i13
        [ i13, entry.id, edition.id ]
      end

      if entry.kind == "wishlist"
        i13 = entry.isbn13 || (entry.isbn10 && Isbn.to_13(entry.isbn10))
        rows << [ i13, entry.id, nil ] if i13
      end

      (@related_isbns[entry.id] || []).each do |i13|
        rows << [ i13, entry.id, nil ] unless owned.include?(i13)
      end

      rows
    end

    # {entry_id => [ISBN-13, ...]} for the other printings ISFDB knows of
    # each owned work — read straight from the WorkSiblingIsbns cache
    # (Isfdb::SiblingIsbnRefresh keeps it current, off the build's
    # critical path). No network here.
    def load_related_isbns(view)
      work_ids = view.entries.filter_map { |e| e.id.delete_prefix("work:").to_i if e.kind == "work" }
      WorkSiblingIsbns.for_works(work_ids).transform_keys { |id| "work:#{id}" }
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
      WishlistItem.where(id: wishlist_ids).includes(cover_image_attachment: :blob).find_each do |w|
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

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
          "INSERT INTO editions VALUES (?,?,?,?,?,?,?,?,?)",
          [
            edition.id, entry.id, edition.format, edition.format_detail, edition.publisher,
            edition.year&.to_i, edition.isbn10, edition.isbn13, blob(thumbs["edition:#{edition.id}"])
          ]
        )
      end

      isbn_rows(entry).each { |row| db.execute("INSERT INTO isbn_index VALUES (?,?,?)", row) }
    end

    # Every ISBN this entry can be scanned by, folded to ISBN-13.
    def isbn_rows(entry)
      rows = entry.editions.filter_map do |edition|
        i13 = edition.isbn13 || (edition.isbn10 && Isbn.to_13(edition.isbn10))
        [ i13, entry.id, edition.id ] if i13
      end
      if entry.kind == "wishlist"
        i13 = entry.isbn13 || (entry.isbn10 && Isbn.to_13(entry.isbn10))
        rows << [ i13, entry.id, nil ] if i13
      end
      rows
    end

    def write_meta(db, entry_count)
      {
        version: @version, generated_at: @generated_at.iso8601, entry_count: entry_count
      }.each { |k, v| db.execute("INSERT INTO meta VALUES (?,?)", [ k.to_s, v.to_s ]) }
    end

    # One pass over the covers that ShopView flagged, keyed the same way
    # the entry/edition rows are. A thumb that fails to render is skipped,
    # not fatal.
    def load_thumbs(view)
      edition_ids = view.entries.flat_map { |e| e.editions.select(&:has_cover).map(&:id) }
      wishlist_ids = view.entries.select { |e| e.kind == "wishlist" && e.has_cover }
                        .map { |e| e.id.delete_prefix("wishlist:").to_i }

      thumbs = {}
      Edition.where(id: edition_ids).find_each do |edition|
        bytes = thumb_bytes(edition)
        thumbs["edition:#{edition.id}"] = bytes if bytes
      end
      WishlistItem.where(id: wishlist_ids).find_each do |item|
        bytes = thumb_bytes(item)
        thumbs["wishlist:#{item.id}"] = bytes if bytes
      end
      thumbs
    end

    def thumb_bytes(record)
      record.cover_image.variant(:thumb).processed.download
    rescue StandardError => e
      Rails.logger.warn("mobile snapshot: :thumb failed for #{record.class}##{record.id} — #{e.message}")
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

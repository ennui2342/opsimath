require "test_helper"
require "sqlite3"

module Mobile
  class SnapshotBuilderTest < ActiveSupport::TestCase
    PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    setup do
      @work = Work.create!(title: "Neuromancer", literary_form: "novel", original_publication_year: 1984)
      WorkContributor.create!(work: @work, contributor: Contributor.create!(name: "William Gibson"), role: "author", display_order: 0)
      @edition = Edition.create!(format: "paperback", publisher: "Ace Books", publish_date: "1984", page_count: 271)
      EditionContent.create!(work: @work, edition: @edition)
      EditionIdentifier.create!(edition: @edition, id_type: "isbn13", value: "9780441569595")
      EditionIdentifier.create!(edition: @edition, id_type: "isfdb", value: "55210")
      @edition.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")
      Copy.create!(edition: @edition, disposition: "owned")

      @wishlist = WishlistItem.create!(title: "Vagabonds", author_name: "Hao Jingfang",
                                       external_ids: { "isbn13" => "9781534422087", "isbn10" => "1534422080" })
    end

    def build_and_open
      @result = SnapshotBuilder.build(version: 7)
      @path = Tempfile.new([ "snap", ".sqlite3" ]).path
      IO.copy_stream(@result.io, @path)
      db = SQLite3::Database.new(@path)
      db.results_as_hash = true
      db
    end

    teardown { @result&.io&.close }

    test "one entry per work and wishlist item, with search columns" do
      db = build_and_open
      assert_equal 2, @result.entry_count

      work = db.execute("SELECT * FROM entries WHERE kind = 'work'").first
      assert_equal "work:#{@work.id}", work["id"]
      assert_equal "William Gibson", work["authors"]
      assert_equal 1, work["owned"]
      assert_equal 0, work["wishlisted"]
      assert_equal "neuromancer", work["search_title"]

      wl = db.execute("SELECT * FROM entries WHERE kind = 'wishlist'").first
      assert_equal "Vagabonds", wl["title"]
      assert_equal "9781534422087", wl["isbn13"]
      assert_equal 1, wl["wishlisted"]
    end

    test "owned editions hang off the work entry, carrying ISBNs, page count, disposition and linkable ids" do
      db = build_and_open
      editions = db.execute("SELECT entry_id, publisher, page_count, disposition, isbn13, isfdb, goodreads FROM editions")
      assert_equal 1, editions.size
      assert_equal "work:#{@work.id}", editions.first["entry_id"]
      assert_equal "Ace Books", editions.first["publisher"]
      assert_equal 271, editions.first["page_count"]
      assert_equal "owned", editions.first["disposition"]
      assert_equal "9780441569595", editions.first["isbn13"]
      assert_equal "55210", editions.first["isfdb"]
      assert_nil editions.first["goodreads"]
    end

    test "a retired edition is exported as a card and indexed against its own edition_id" do
      retired = Edition.create!(publisher: "Grafton UK")
      EditionContent.create!(work: @work, edition: retired)
      EditionIdentifier.create!(edition: retired, id_type: "isbn13", value: "9780586213872")
      Copy.create!(edition: retired, disposition: "replaced")

      db = build_and_open

      rows = db.execute("SELECT publisher, disposition FROM editions WHERE entry_id = ? ORDER BY disposition", "work:#{@work.id}")
      assert_equal [ [ "Ace Books", "owned" ], [ "Grafton UK", "replaced" ] ], rows.map { |r| [ r["publisher"], r["disposition"] ] }

      # scanning the retired printing resolves to the work with its own card matched
      row = db.execute("SELECT entry_id, edition_id FROM isbn_index WHERE isbn13 = ?", "9780586213872").first
      assert_equal "work:#{@work.id}", row["entry_id"]
      assert_equal retired.id, row["edition_id"]
    end

    test "embeds the :thumb as a WebP BLOB, and caches it in MobileThumb" do
      db = build_and_open
      thumb = db.execute("SELECT thumb FROM editions").first["thumb"]
      assert thumb.is_a?(String)
      assert thumb.start_with?("RIFF"), "expected a WebP (RIFF) blob"

      key = @edition.cover_image.variant(:thumb).processed.key
      assert_equal thumb, MobileThumb.fetch([ key ])[key], "the miss should have backfilled the cache"
    end

    test "a cached MobileThumb is used verbatim, without re-downloading the blob" do
      key = @edition.cover_image.variant(:thumb).processed.key
      MobileThumb.store(key, "CACHED BYTES")

      db = build_and_open
      thumb = db.execute("SELECT thumb FROM editions").first["thumb"]
      assert_equal "CACHED BYTES".b, thumb
    end

    test "isbn_index folds every ISBN to ISBN-13 for exact lookup" do
      db = build_and_open
      rows = db.execute("SELECT isbn13, entry_id, edition_id FROM isbn_index ORDER BY isbn13")
        .map { |r| [ r["isbn13"], r["entry_id"], r["edition_id"] ] }
      assert_equal [
        [ "9780441569595", "work:#{@work.id}", @edition.id ],
        [ "9781534422087", "wishlist:#{@wishlist.id}", nil ]
      ], rows
    end

    test "the WorkSiblingIsbns cache widens the index for an owned work" do
      WorkSiblingIsbns.create!(
        work_id: @work.id, refreshed_at: Time.current, queried_isbns: [ "9780441569595" ],
        isbn13s: [ "9780441569595", "9780722186978", "9780586066451" ] # own printing + two siblings
      )

      db = build_and_open

      rows = db.execute("SELECT isbn13, entry_id, edition_id FROM isbn_index")
        .map { |r| [ r["isbn13"], r["entry_id"], r["edition_id"] ] }
      wid = "work:#{@work.id}"
      assert_includes rows, [ "9780441569595", wid, @edition.id ]       # owned edition — the exact match
      assert_includes rows, [ "9780722186978", wid, nil ]               # sibling printing -> work, no edition
      assert_includes rows, [ "9780586066451", wid, nil ]
      assert_equal 1, rows.count { |i13, _, _| i13 == "9780441569595" } # not also added as a null row
    end

    test "meta carries version, entry count, generation time" do
      db = build_and_open
      meta = db.execute("SELECT key, value FROM meta").to_h { |r| [ r["key"], r["value"] ] }
      assert_equal "7", meta["version"]
      assert_equal "2", meta["entry_count"]
      assert_equal @result.generated_at.iso8601, meta["generated_at"]
    end
  end
end

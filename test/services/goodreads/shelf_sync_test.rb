require "test_helper"

module Goodreads
  class ShelfSyncTest < ActiveSupport::TestCase
    setup do
      # Every auto-create touches ensure_fiction_subject, which requires
      # the seeded "Fiction" Subject to exist (db/seeds.rb).
      Subject.create!(name: "Fiction", ddc_code: "800")
    end

    def fixture_item(shelf, goodreads_book_id)
      client = RssClient.allocate
      body = File.read(Rails.root.join("test/fixtures/files/goodreads_#{shelf}_sample.xml"))
      client.send(:parse, body).find { |i| i.goodreads_book_id == goodreads_book_id }
    end

    test "wishlist creates a WishlistItem and only a WishlistItem" do
      item = fixture_item("wishlist", "29363290")

      outcome = ShelfSync.sync(item, "wishlist", {})

      wishlist_item = WishlistItem.find_by!(external_ids: { "goodreads" => "29363290" })
      assert_equal "A Greater Music", wishlist_item.title
      assert_equal "Bae Suah", wishlist_item.author_name
      assert_equal wishlist_item, outcome.entity
      assert_not Work.exists?(title: "A Greater Music")
    end

    test "wishlist is idempotent — syncing the same item twice doesn't duplicate" do
      item = fixture_item("wishlist", "29363290")
      ShelfSync.sync(item, "wishlist", {})
      ShelfSync.sync(item, "wishlist", {})

      assert_equal 1, WishlistItem.where(external_ids: { "goodreads" => "29363290" }).count
    end

    test "to-read auto-creates Work/Edition/Copy for a genuinely new book" do
      item = fixture_item("to_read", "61030535") # Children of Memory — never in the CSV export

      ShelfSync.sync(item, "to-read", {})

      work = Work.find_by!(title: "Children of Memory") # series suffix stripped by RowParser.series_info
      assert_equal "Adrian Tchaikovsky", work.contributors.sole.name
      assert_equal 2022, work.original_publication_year # book_published is work-level, not edition-level
      edition = work.editions.sole
      assert_nil edition.publish_date # left for isfdb enrichment — book_published isn't this edition's date
      assert_nil edition.format # no signal from the feed — left for isfdb enrichment, not fabricated
      assert_equal "0316466409", edition.edition_identifiers.find_by(id_type: "isbn10").value
      assert_equal 1, edition.copies.count
      assert edition.cover_image.attached?
    end

    test "a cover download failure doesn't block cataloging the rest of the item" do
      WebMock.reset!
      stub_request(:get, /i\.gr-assets\.com/).to_return(status: 500)
      item = fixture_item("to_read", "61030535")

      ShelfSync.sync(item, "to-read", {})

      edition = Work.find_by!(title: "Children of Memory").editions.sole
      assert_not edition.cover_image.attached?
      assert_equal "0316466409", edition.edition_identifiers.find_by(id_type: "isbn10").value
    end

    test "to-read deletes the matching WishlistItem — the real wishlist-to-catalog transition" do
      WishlistItem.create!(title: "Europe at Dawn", author_name: "Dave Hutchinson", external_ids: { "goodreads" => "39666185" })
      item = fixture_item("to_read", "39666185")

      ShelfSync.sync(item, "to-read", {})

      assert_not WishlistItem.exists?(external_ids: { "goodreads" => "39666185" })
      assert Work.exists?(title: "Europe at Dawn") # series suffix stripped by RowParser.series_info
    end

    test "currently-reading auto-creates and opens a Reading for a book with no prior history at all" do
      item = fixture_item("currently_reading", "256246282") # the real Clarkesworld magazine case

      outcome = ShelfSync.sync(item, "currently-reading", {})

      work = Work.find_by!(title: "Clarkesworld Magazine, Issue 238, July 2026")
      assert_equal "periodical", work.literary_form
      reading = work.readings.sole
      assert_equal "reading", reading.status
      assert_equal Date.new(2026, 8, 4), reading.date_started
      assert_equal reading, outcome.entity
    end

    test "currently-reading is a no-op when a Reading is already open for the matched work" do
      work = Work.create!(title: "The Solaris Book of New Science Fiction", literary_form: "anthology")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "95562")
      existing_reading = Reading.create!(work: work, edition: edition, status: "reading", date_started: Date.new(2026, 1, 30))

      item = fixture_item("currently_reading", "95562")
      ShelfSync.sync(item, "currently-reading", {})

      assert_equal 1, work.readings.count
      assert_equal Date.new(2026, 1, 30), existing_reading.reload.date_started # untouched, not overwritten
    end

    test "currently-reading flags reread_conflict instead of guessing when the work was already read" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2010, 5, 1))

      item = fixture_item("read", "953070")
      ShelfSync.sync(item, "currently-reading", {})

      assert_equal 1, work.readings.count # no new Reading opened
      pending = PendingDecision.where(kind: "reread_conflict").last
      assert_equal "953070", pending.payload["goodreads_book_id"]
      assert_equal "2026-08-03", pending.payload["date_started"] # carried forward for PendingDecisionResolver to act on
    end

    test "read closes the real open Neuromancer Reading — the confirmed genuine reread" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      open_reading = Reading.create!(work: work, edition: edition, status: "reading", date_started: Date.new(2010, 4, 17))

      item = fixture_item("read", "953070")
      outcome = ShelfSync.sync(item, "read", {})

      open_reading.reload
      assert_equal "completed", open_reading.status
      assert_equal Date.new(2026, 7, 28), open_reading.date_finished
      assert_equal 5.0, open_reading.rating
      assert_equal open_reading, outcome.entity
      assert Review.exists?(reading: open_reading)
    end

    test "read doesn't duplicate the Reading when re-synced after only the rating changed" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      Reading.create!(work: work, edition: edition, status: "reading", date_started: Date.new(2010, 4, 17))

      item = fixture_item("read", "953070")
      first = ShelfSync.sync(item, "read", {})
      second = ShelfSync.sync(item, "read", first.payload) # simulates Syncer passing the remembered reading_id forward

      assert_equal 1, work.readings.count
      assert_equal first.entity, second.entity
    end

    test "read reuses an existing completed Reading with no prior GoodreadsSyncState (Phase-1-style) instead of duplicating it" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      # No date_started, no rating, no review — Importer's dateless-start
      # shape for a row that only ever had a Date Read, plus no
      # GoodreadsSyncState row (Importer never writes one) — exactly the
      # Phase-1-then-Phase-2 scenario that caused the real duplication bug.
      phase1_reading = Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2026, 7, 28))

      item = fixture_item("read", "953070")
      outcome = ShelfSync.sync(item, "read", {})

      assert_equal 1, work.readings.count # no duplicate created
      assert_equal phase1_reading, outcome.entity
      assert_equal 5.0, phase1_reading.reload.rating
      assert Review.exists?(reading: phase1_reading)
    end

    test "did-not-finish sets status dnf" do
      item = fixture_item("did_not_finish", "17823844")

      outcome = ShelfSync.sync(item, "did-not-finish", {})

      reading = Reading.find(outcome.entity.id)
      assert_equal "dnf", reading.status
      assert_equal Date.new(2024, 5, 3), reading.date_finished
    end
  end
end

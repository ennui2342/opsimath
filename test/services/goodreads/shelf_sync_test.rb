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

      wishlist_item = WishlistItem.find_by!("external_ids ->> 'goodreads' = ?", "29363290")
      assert_equal "A Greater Music", wishlist_item.title
      assert_equal "Bae Suah", wishlist_item.author_name
      assert_equal "1940953464", wishlist_item.external_ids["isbn10"] # captured for shop-scan matching
      assert_equal "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1469296531l/29363290._SY475_.jpg", wishlist_item.cover_url
      assert wishlist_item.cover_image.attached? # downloaded for the shop-lookup :thumb
      assert_equal wishlist_item, outcome.entity
      assert_not Work.exists?(title: "A Greater Music")
      assert outcome.created
      assert outcome.changed
    end

    test "wishlist is idempotent — syncing the same item twice doesn't duplicate" do
      item = fixture_item("wishlist", "29363290")
      ShelfSync.sync(item, "wishlist", {})
      ShelfSync.sync(item, "wishlist", {})

      assert_equal 1, WishlistItem.where("external_ids ->> 'goodreads' = ?", "29363290").count
    end

    test "wishlist is a no-op (changed: false) when the item is already on the wishlist — the real notification bug" do
      # Real bug, found live in production (2026-08-08): a cold-start
      # resync (every GoodreadsSyncState wiped) re-touched every wishlist
      # item regardless of whether it was already there from the CSV
      # import. ShelfSync#wishlist itself always correctly made zero
      # writes for an already-present item — but GoodreadsSyncJob had no
      # way to tell that apart from a genuine addition, and notified
      # "Added to wishlist" for ~100 books that had been there for ages.
      WishlistItem.create!(title: "A Greater Music", author_name: "Bae Suah", external_ids: { "goodreads" => "29363290" })
      item = fixture_item("wishlist", "29363290")

      outcome = ShelfSync.sync(item, "wishlist", {})

      assert_not outcome.created
      assert_not outcome.changed
      assert_equal 1, WishlistItem.where(external_ids: { "goodreads" => "29363290" }).count
    end

    test "to-read auto-creates Work/Edition/Copy for a genuinely new book" do
      item = fixture_item("to_read", "61030535") # Children of Memory — never in the CSV export

      outcome = ShelfSync.sync(item, "to-read", {})
      assert outcome.created
      assert outcome.changed

      work = Work.find_by!(title: "Children of Memory") # series suffix stripped by RowParser.series_info
      assert_equal "Adrian Tchaikovsky", work.contributors.sole.name
      assert_equal 2022, work.original_publication_year # book_published is work-level, not edition-level
      edition = work.editions.sole
      assert_nil edition.publish_date # left for isfdb enrichment — book_published isn't this edition's date
      assert_nil edition.format # no signal from the feed — left for isfdb enrichment, not fabricated
      assert_equal "0316466409", edition.edition_identifiers.find_by(id_type: "isbn10").value
      assert_equal "9780316466400", edition.edition_identifiers.find_by(id_type: "isbn13").value # derived — RSS only carries isbn10
      assert_equal 1, edition.copies.count
      assert edition.cover_image.attached?
      assert_equal "goodreads", edition.field_sources["cover_image"]
      # Audit parity with CSV import — a real EnrichmentRecord exists even
      # though the RSS feed carries no field data to apply here.
      assert EnrichmentRecord.exists?(entity: edition, provider: "goodreads", external_id: "61030535")
    end

    test "the RSS status shelf is never turned into a Genre/Subject/Tag on an auto-created book" do
      # <user_shelves> conflates the exclusive shelf with real custom
      # shelves; a literal "to-read"/"currently-reading" Tag would show as
      # a lozenge on the work page forever.
      ShelfSync.sync(fixture_item("to_read", "61030535"), "to-read", {})
      ShelfSync.sync(fixture_item("currently_reading", "256246282"), "currently-reading", {})

      assert_empty Tag.where(name: RowParser::STATUS_SHELVES)
      assert_empty Genre.where(name: RowParser::STATUS_SHELVES)
      assert_empty Subject.where(name: RowParser::STATUS_SHELVES)
      assert_not Work.find_by!(title: "Children of Memory").tags.exists?(name: "to-read")
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

      outcome = ShelfSync.sync(item, "to-read", {})

      assert_not WishlistItem.exists?(external_ids: { "goodreads" => "39666185" })
      assert Work.exists?(title: "Europe at Dawn") # series suffix stripped by RowParser.series_info
      assert outcome.changed # a real transition happened, even though the edition itself already existed
    end

    test "to-read is a no-op (changed: false) when matching an already-catalogued edition with no wishlist entry to remove" do
      work = Work.create!(title: "Europe at Dawn", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "39666185")
      item = fixture_item("to_read", "39666185")

      outcome = ShelfSync.sync(item, "to-read", {})

      assert_not outcome.created
      assert_not outcome.changed
    end

    test "to-read backfills a goodreads cover onto an already-matched edition with none — the CSV import gap" do
      # A CSV-imported edition has a goodreads EditionIdentifier but no
      # cover at all — the CSV export carries no image URL column, only
      # the RSS feed does. The first ongoing sync pass is the first real
      # chance to backfill it.
      work = Work.create!(title: "Children of Memory", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "61030535")
      item = fixture_item("to_read", "61030535")

      ShelfSync.sync(item, "to-read", {})

      edition.reload
      assert edition.cover_image.attached?
      assert_equal "fake-cover-bytes", edition.cover_image.download
      assert_equal "goodreads", edition.field_sources["cover_image"]
      record = EnrichmentRecord.find_by!(entity: edition, provider: "goodreads", external_id: "61030535")
      assert record.cover_image.attached?
    end

    test "to-read never silently overwrites an edition's existing cover — a genuine difference flags a conflict instead" do
      # Policy simplified deliberately (Mark, 2026-08-08): no per-source
      # trust hierarchy — a populated destination always goes to review
      # on any byte difference, regardless of source. Not "isfdb wins,"
      # not "silently keep the old one" — a real conflict either way.
      work = Work.create!(title: "Children of Memory", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "61030535")
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "isfdb.jpg", content_type: "image/jpeg")
      edition.update!(field_sources: { "cover_image" => "isfdb" })
      item = fixture_item("to_read", "61030535")

      ShelfSync.sync(item, "to-read", {})

      edition.reload
      assert_equal "isfdb-bytes", edition.cover_image.download # untouched pending review
      assert_equal "isfdb", edition.field_sources["cover_image"]
      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal "goodreads", decision.payload["source"]
      assert_includes decision.payload["fields"], "cover_image"
    end

    test "to-read is a no-op on cover when the RSS-proposed cover is byte-identical to what's already attached" do
      work = Work.create!(title: "Children of Memory", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "61030535")
      edition.cover_image.attach(io: StringIO.new("fake-cover-bytes"), filename: "same.jpg", content_type: "image/jpeg")
      edition.update!(field_sources: { "cover_image" => "isfdb" })
      item = fixture_item("to_read", "61030535")

      ShelfSync.sync(item, "to-read", {})

      edition.reload
      assert_equal "fake-cover-bytes", edition.cover_image.download
      assert_equal "isfdb", edition.field_sources["cover_image"] # untouched — no reason to relabel a non-conflict
      assert_equal 0, PendingDecision.count
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
      assert outcome.changed
    end

    test "currently-reading is a no-op (changed: false) when a Reading is already open for the matched work" do
      # Real bug, found live in production (2026-08-08): a cold-start
      # resync re-touched books already marked "reading," with zero real
      # writes behind the touch (the comment right above this branch in
      # ShelfSync already called it a no-op) — but it still notified
      # "Started reading" for books started ages ago.
      work = Work.create!(title: "The Solaris Book of New Science Fiction", literary_form: "anthology")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "95562")
      existing_reading = Reading.create!(work: work, edition: edition, status: "reading", date_started: Date.new(2026, 1, 30))

      item = fixture_item("currently_reading", "95562")
      outcome = ShelfSync.sync(item, "currently-reading", {})

      assert_equal 1, work.readings.count
      assert_equal Date.new(2026, 1, 30), existing_reading.reload.date_started # untouched, not overwritten
      assert_not outcome.changed
    end

    test "currently-reading flags reread_conflict when *this* edition was already read" do
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

    test "currently-reading on a *different* edition than the completed read just opens a new Reading — no conflict" do
      # The EditionReconciliation change_edition case: read the old printing,
      # acquired a new one, now reading that. Unambiguous new read.
      work = Work.create!(title: "Downbelow Station", literary_form: "novel")
      old_edition = Edition.create!(publisher: "Mandarin")
      new_edition = Edition.create!(publisher: "DAW Books")
      EditionContent.create!(work: work, edition: old_edition)
      EditionContent.create!(work: work, edition: new_edition)
      EditionIdentifier.create!(edition: new_edition, id_type: "goodreads", value: "953070")
      Reading.create!(work: work, edition: old_edition, status: "completed", date_finished: Date.new(2015, 1, 1))

      outcome = ShelfSync.sync(fixture_item("read", "953070"), "currently-reading", {})

      assert_empty PendingDecision.where(kind: "reread_conflict")
      new_reading = work.readings.where(edition: new_edition).sole
      assert_equal "reading", new_reading.status
      assert_equal "completed", work.readings.find_by(edition: old_edition).status # first read untouched
      assert_equal new_reading, outcome.entity
      assert outcome.changed
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
      review = Review.find_by!(reading: open_reading)
      assert_not_includes review.text, "<br" # stored as Markdown, not the feed's HTML
      assert_includes review.text, "\n\n"
      assert outcome.changed
    end

    test "read is a no-op (changed: false) when re-touched with identical values already on file" do
      # Real bug, found live in production (2026-08-08): a cold-start
      # resync re-touched every read-shelf item regardless of whether
      # its rating/date/review already matched what was on file (from
      # the CSV import) — reading.save! always ran and always looked
      # like a real event to the old, unconditional notification code.
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      existing_reading = Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2026, 7, 28), rating: 5.0)
      Review.create!(work: work, reading: existing_reading, text: "great book", status: "published", channels: [ { "channel" => "goodreads" } ])

      item = fixture_item("read", "953070") # same date, same 5.0 rating, has a review
      outcome = ShelfSync.sync(item, "read", {})

      assert_equal existing_reading, outcome.entity
      assert_equal 1, work.readings.count
      assert_not outcome.changed
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
      assert outcome.changed # real new information: rating and review filled in
    end

    test "read reuses an existing dateless completed Reading on the same edition instead of duplicating it" do
      # Real bug, found live in production (2026-08-08): a cold-start
      # resync (every GoodreadsSyncState wiped) re-touched books whose
      # CSV import had created a dateless completed Reading (Importer's
      # own deliberate "ordinary single-read, no dates" case). Since the
      # RSS item was *also* dateless, matching_completed_reading's old
      # date-based lookup never even ran (guarded on user_read_at.present?),
      # so every one of these landed as a genuine duplicate Reading on
      # the exact same edition — 12 real titles in the actual library.
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
      phase1_reading = Reading.create!(work: work, edition: edition, status: "completed") # no date_finished at all

      item = RssClient::FeedItem.new(**fixture_item("read", "953070").to_h.merge(user_read_at: nil, user_rating: nil, user_review: nil))
      outcome = ShelfSync.sync(item, "read", {})

      assert_equal 1, work.readings.count # no duplicate created
      assert_equal phase1_reading, outcome.entity
    end

    test "read does NOT collapse two dateless completed Readings on different editions of the same work" do
      # The narrower, deliberate boundary of the fix above: two genuinely
      # separate dateless reads of two *different* editions stay
      # legitimately ambiguous — same reasoning the dated branch already
      # applies by staying work-scoped, not edition-scoped, for its own
      # match. Edition-scoping the dateless branch must not accidentally
      # widen to work-scoping and merge these.
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      other_edition = Edition.create!
      matched_edition = Edition.create!
      EditionContent.create!(work: work, edition: other_edition)
      EditionContent.create!(work: work, edition: matched_edition)
      EditionIdentifier.create!(edition: matched_edition, id_type: "goodreads", value: "953070")
      existing_reading = Reading.create!(work: work, edition: other_edition, status: "completed")

      item = RssClient::FeedItem.new(**fixture_item("read", "953070").to_h.merge(user_read_at: nil, user_rating: nil, user_review: nil))
      outcome = ShelfSync.sync(item, "read", {})

      assert_equal 2, work.readings.count # a new Reading, not merged into the other edition's
      assert_not_equal existing_reading, outcome.entity
      assert_equal matched_edition, outcome.entity.edition
    end

    test "did-not-finish sets status dnf" do
      item = fixture_item("did_not_finish", "17823844")

      outcome = ShelfSync.sync(item, "did-not-finish", {})

      reading = Reading.find(outcome.entity.id)
      assert_equal "dnf", reading.status
      assert_equal Date.new(2024, 5, 3), reading.date_finished
    end

    # --- edition reconciliation (title+author match, no confident edition) ---

    def title_author_item(shelf, title:, author:, gr_id:, isbn: nil, **extra)
      RssClient::FeedItem.new(goodreads_book_id: gr_id, title: title, author_name: author, isbn: isbn, **extra)
    end

    def owned_work_with_edition(title:, author:, gr_id:, isbn10: nil)
      work = Work.create!(title: title, literary_form: "novel")
      WorkContributor.create!(work: work, contributor: Contributor.create!(name: author), role: "author")
      edition = Edition.create!(format: "paperback")
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: gr_id)
      EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: isbn10) if isbn10
      Copy.create!(edition: edition, disposition: "owned")
      [ work, edition ]
    end

    test "a title+author-only match raises an EditionReconciliation instead of binding an edition" do
      work, edition = owned_work_with_edition(title: "Facets", author: "Walter Jon Williams", gr_id: "3945054", isbn10: "0586213872")
      item = title_author_item("read", title: "Facets", author: "Walter Jon Williams", gr_id: "1343099", isbn: "0812564022", user_read_at: "2024-02-01")

      outcome = ShelfSync.sync(item, "read", {})

      rec = EditionReconciliation.sole
      assert_equal work, rec.work
      assert_equal "1343099", rec.incoming_goodreads_id
      assert_equal "read", rec.shelf
      assert_equal [ edition.id ], rec.payload["candidate_edition_ids"]
      assert_equal rec, outcome.entity
      assert_empty work.readings                      # deferred, not opened
      assert_nil edition.reload.enrichment_records.find_by(provider: "goodreads") # no cover record
    end

    test "the reconciliation is deduped and its payload refreshed on a re-touch" do
      owned_work_with_edition(title: "Facets", author: "Walter Jon Williams", gr_id: "3945054")
      base = { title: "Facets", author: "Walter Jon Williams", gr_id: "1343099" }

      ShelfSync.sync(title_author_item("read", **base, user_rating: "3"), "read", {})
      ShelfSync.sync(title_author_item("read", **base, user_rating: "5"), "read", {})

      assert_equal 1, EditionReconciliation.count
      assert_equal "5", EditionReconciliation.sole.payload.dig("feed_item", "user_rating")
    end

    test "a confident (goodreads_book_id) match still opens a Reading with source: owned_copy" do
      _work, edition = owned_work_with_edition(title: "Blindsight", author: "Peter Watts", gr_id: "48484")
      item = title_author_item("read", title: "Blindsight", author: "Peter Watts", gr_id: "48484", user_read_at: "2024-03-03")

      outcome = ShelfSync.sync(item, "read", {})

      assert_equal edition, outcome.entity.edition
      assert_equal "owned_copy", outcome.entity.source
      assert_equal 0, EditionReconciliation.count
    end
  end
end

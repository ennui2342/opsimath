require "test_helper"

module Goodreads
  class ImporterTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/goodreads_sample.csv")

    setup do
      # Every import touches ensure_fiction_subject, which requires the
      # seeded "Fiction" Subject to exist (db/seeds.rb) — unlike Genre,
      # not optional per-test, so seeded once here rather than repeated
      # in every test.
      Subject.create!(name: "Fiction", ddc_code: "800")
    end

    test "imports a normal single-read row with review and rating" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Jewel-hinged Jaw: Notes on the Language of Science Fiction")
      assert_equal "Samuel R. Delany", work.contributors.sole.name
      assert_equal "essay", work.literary_form

      reading = work.readings.sole
      assert_equal "completed", reading.status
      assert_equal Date.new(2026, 2, 10), reading.date_started
      assert_equal Date.new(2026, 7, 21), reading.date_finished
      assert_equal 5.0, reading.rating

      review = Review.find_by!(work: work)
      assert_equal "published", review.status
      assert_equal 5.0, review.rating
      assert_equal [ { "channel" => "goodreads" } ], review.channels

      edition = work.editions.sole
      assert_equal "1978", edition.publish_date # year only, from Year Published — an EDTF string
      assert_nil edition.page_count # no longer imported from Goodreads at all — left to isfdb enrichment
    end

    test "a wishlist row creates only a WishlistItem, no Work/Edition/Copy" do
      Importer.import(FIXTURE)

      assert_not Work.exists?(title: "Vagabonds")
      item = WishlistItem.find_by!(title: "Vagabonds")
      assert_equal "Hao Jingfang", item.author_name
      assert_equal "49454725", item.external_ids["goodreads"]
      assert_equal "9781534422087", item.external_ids["isbn13"]
    end

    test "a currently-reading row opens a Reading with date_started from Date Added" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Existentialism from Dostoevsky to Sartre")
      reading = work.readings.sole
      assert_equal "reading", reading.status
      assert_equal Date.new(2025, 6, 19), reading.date_started
      assert_nil reading.date_finished
    end

    test "a did-not-finish row uses the same date/rating policy as read, with status dnf" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Unknown Craftsman: A Japanese Insight into Beauty")
      reading = work.readings.sole
      assert_equal "dnf", reading.status
      assert_equal Date.new(2024, 4, 4), reading.date_started
      assert_equal Date.new(2024, 5, 3), reading.date_finished
      assert_equal 1.0, reading.rating
    end

    test "two editions of the same to-read work share one Work and create no Reading" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Midnight Library")
      assert_equal 2, work.editions.count
      assert_equal 2, Copy.where(edition: work.editions).count
      assert_equal 0, work.readings.count
    end

    test "additional authors are linked as further WorkContributor author rows" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Color of Neanderthal Eyes / And Strange at Ecbatan the Trees")
      names = work.work_contributors.order(:display_order).map { |wc| wc.contributor.name }
      assert_equal [ "James Tiptree Jr.", "Michael Bishop" ], names
    end

    test "a fiction Work with no genre/subject shelf signal at all still gets the structural Fiction Subject" do
      Importer.import(FIXTURE)

      # Real row: Bookshelves is just "to-read" — no sci-fi tag, no
      # subject tag, nothing to match against. This is the ordinary case
      # for most of the real collection (Mark doesn't re-tag every book
      # "sci-fi" when the whole shelf already implies it).
      work = Work.find_by!(title: "The Color of Neanderthal Eyes / And Strange at Ecbatan the Trees")
      assert_equal [ "Fiction" ], work.subjects.pluck(:name)
    end

    test "a real nonfiction Subject match wins over the structural Fiction default" do
      Subject.create!(name: "History", ddc_code: "900")

      Importer.import(FIXTURE)

      work = Work.find_by!(title: "SPQR: A History of Ancient Rome")
      assert_equal [ "History" ], work.subjects.pluck(:name)
    end

    test "multiple nonfiction Subject labels on one row all attach, no Fiction" do
      Subject.create!(name: "Artificial intelligence", ddc_code: "000")
      Subject.create!(name: "Business")

      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Reshuffle: Who wins when AI restacks the knowledge economy")
      assert_equal [ "Artificial intelligence", "Business" ], work.subjects.order(:name).pluck(:name)
    end

    test "an essay (nonfiction) Work gets no Fiction Subject, even with no other Subject match" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Jewel-hinged Jaw: Notes on the Language of Science Fiction")
      assert_equal "essay", work.literary_form
      assert_equal 0, work.subjects.count
    end

    test "a read row with no date signal at all still gets exactly one Reading with nil dates" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Heavy Weather")
      reading = work.readings.sole
      assert_equal "completed", reading.status
      assert_nil reading.date_started
      assert_nil reading.date_finished
      assert_nil reading.rating
    end

    test "a Bookshelves label with no matching Genre becomes a Tag" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Heavy Weather")
      assert_equal [ "sci-fi" ], work.tags.pluck(:name)
      assert_equal 0, work.genres.count
    end

    test "anthology/collection Bookshelves labels set Work.literary_form instead of becoming a Tag or Genre" do
      Genre.create!(name: "Science fiction", thema_code: "FL")

      Importer.import(FIXTURE)

      # Both real rows are shelved "anthology, sci-fi" / "sci-fi,
      # collection" — the structural label should be consumed into
      # literary_form, leaving only the real "sci-fi" -> Science fiction
      # Genre behind, no redundant anthology/collection Tag or Genre.
      anthology_work = Work.find_by!(title: "The Ruins of Earth")
      assert_equal "anthology", anthology_work.literary_form
      assert_equal 0, anthology_work.tags.count
      assert_equal [ "Science fiction" ], anthology_work.genres.pluck(:name)

      collection_work = Work.find_by!(title: "The Adventures of Alyx")
      assert_equal "collection", collection_work.literary_form
      assert_equal 0, collection_work.tags.count
      assert_equal [ "Science fiction" ], collection_work.genres.pluck(:name)
    end

    test "a Bookshelves label matching a seeded Genre becomes a WorkGenre, not a Tag" do
      Genre.create!(name: "Science fiction", thema_code: "FL")

      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Heavy Weather")
      assert_equal [ "Science fiction" ], work.genres.pluck(:name)
      assert_equal 0, work.tags.count
    end

    test "duplicate read-shelf rows for the same work collapse to one real Reading regardless of file order" do
      Importer.import(FIXTURE)

      vast = Work.find_by!(title: "Vast")
      assert_equal 2, vast.editions.count
      assert_equal 1, vast.readings.count
      assert_equal 5.0, vast.readings.sole.rating

      parasite = Work.find_by!(title: "Parasite")
      assert_equal 1, parasite.readings.count
      assert_equal 3.0, parasite.readings.sole.rating
      assert Review.exists?(work: parasite)

      # Burning Dark: the empty-duplicate row appears BEFORE the real,
      # dated row in the real export — the case that would break a naive
      # row-by-row "first row wins" importer.
      burning_dark = Work.find_by!(title: "The Burning Dark")
      assert_equal 1, burning_dark.readings.count
      assert_equal Date.new(2014, 9, 5), burning_dark.readings.sole.date_finished

      # Medusa Chronicles: both rows carry the SAME rating (2.0) — rating
      # alone can't discriminate the real row from the duplicate; only
      # the date can.
      medusa = Work.find_by!(title: "The Medusa Chronicles")
      assert_equal 1, medusa.readings.count
      assert_equal Date.new(2017, 7, 1), medusa.readings.sole.date_finished
      assert_equal 2.0, medusa.readings.sole.rating
    end

    test "re-running the import against the same file is a no-op" do
      Importer.import(FIXTURE)
      before = { works: Work.count, editions: Edition.count, readings: Reading.count, wishlist: WishlistItem.count }

      counts = Importer.import(FIXTURE)

      assert_equal before, { works: Work.count, editions: Edition.count, readings: Reading.count, wishlist: WishlistItem.count }
      assert_equal 0, counts.imported_rows
      assert_equal 0, counts.wishlisted
    end
  end
end

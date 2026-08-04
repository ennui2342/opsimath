require "test_helper"

module Goodreads
  class ImporterTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/goodreads_sample.csv")

    test "imports a normal single-read row with review and rating" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "The Jewel-hinged Jaw: Notes on the Language of Science Fiction")
      assert_equal "Samuel R. Delany", work.contributors.sole.name

      reading = work.readings.sole
      assert_equal "completed", reading.status
      assert_equal Date.new(2026, 2, 10), reading.date_started
      assert_equal Date.new(2026, 7, 21), reading.date_finished
      assert_equal 5.0, reading.rating

      review = Review.find_by!(work: work)
      assert_equal "published", review.status
      assert_equal 5.0, review.rating
      assert_equal [ { "channel" => "goodreads" } ], review.channels
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

    test "a read row with no date signal at all still gets exactly one Reading with nil dates" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Heavy Weather")
      reading = work.readings.sole
      assert_equal "completed", reading.status
      assert_nil reading.date_started
      assert_nil reading.date_finished
      assert_nil reading.rating
    end

    test "an unseeded Bookshelves label becomes a Tag, not a Genre" do
      Importer.import(FIXTURE)

      work = Work.find_by!(title: "Heavy Weather")
      assert_equal [ "sci-fi" ], work.tags.pluck(:name)
      assert_equal 0, work.genres.count
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

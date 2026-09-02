require "test_helper"

module Mobile
  class ShopViewTest < ActiveSupport::TestCase
    PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    test "an owned work: one row, owned true, with its owned editions and ISBNs" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel", original_publication_year: 1984)
      gibson = Contributor.create!(name: "William Gibson")
      WorkContributor.create!(work:, contributor: gibson, role: "author", display_order: 0)
      series = Series.create!(name: "Sprawl")
      WorkSeries.create!(work:, series:, position: 1)

      edition = Edition.create!(format: "paperback", format_detail: "mass_market", publisher: "Ace Books", publish_date: "1984")
      EditionContent.create!(work:, edition:)
      EditionIdentifier.create!(edition:, id_type: "isbn10", value: "0441569595")
      EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780441569595")
      edition.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")
      Copy.create!(edition:, disposition: "owned")

      result = ShopView.build

      assert_equal 1, result.works.size
      row = result.works.sole
      assert_equal "Neuromancer", row.title
      assert_equal [ "William Gibson" ], row.authors
      assert_equal "Sprawl", row.series
      assert_equal "1", row.series_position
      assert row.owned
      assert_not row.wishlisted

      ed = row.editions.sole
      assert_equal "paperback", ed.format
      assert_equal "Ace Books", ed.publisher
      assert_equal "1984", ed.year
      assert_equal "0441569595", ed.isbn10
      assert_equal "9780441569595", ed.isbn13
      assert ed.has_cover
    end

    test "a work with only a non-owned copy is excluded entirely" do
      work = Work.create!(title: "Sold Off", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "sold")

      assert_empty ShopView.build.works
    end

    test "only owned editions of an owned work appear as edition rows" do
      work = Work.create!(title: "Two Printings", literary_form: "novel")
      owned_ed = Edition.create!(publisher: "Gollancz")
      other_ed = Edition.create!(publisher: "Orbit")
      EditionContent.create!(work:, edition: owned_ed)
      EditionContent.create!(work:, edition: other_ed)
      Copy.create!(edition: owned_ed, disposition: "owned")
      Copy.create!(edition: other_ed, disposition: "given_away")

      row = ShopView.build.works.sole
      assert_equal [ "Gollancz" ], row.editions.map(&:publisher)
    end

    test "a wishlisted work matched to a Work folds onto that work's row" do
      work = Work.create!(title: "Wanted", literary_form: "novel")
      WishlistItem.create!(title: "Wanted", work:)

      row = ShopView.build.works.sole
      assert row.wishlisted
      assert_not row.owned
      assert_empty row.editions
    end

    test "an unmatched wishlist entry becomes a wishlist_entries row with ISBNs from external_ids" do
      WishlistItem.create!(
        title: "Vagabonds", author_name: "Hao Jingfang",
        external_ids: { "goodreads" => "49454725", "isbn10" => "1534422080", "isbn13" => "9781534422087" }
      )

      result = ShopView.build
      assert_empty result.works
      entry = result.wishlist_entries.sole
      assert_equal "Vagabonds", entry.title
      assert_equal "Hao Jingfang", entry.author
      assert_equal "1534422080", entry.isbn10
      assert_equal "9781534422087", entry.isbn13
    end

    test "authors come back in display_order" do
      work = Work.create!(title: "Inferno", literary_form: "novel")
      niven = Contributor.create!(name: "Larry Niven")
      pournelle = Contributor.create!(name: "Jerry Pournelle")
      WorkContributor.create!(work:, contributor: pournelle, role: "author", display_order: 1)
      WorkContributor.create!(work:, contributor: niven, role: "author", display_order: 0)
      WorkContributor.create!(work:, contributor: Contributor.create!(name: "An Editor"), role: "editor", display_order: 0)
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "owned")

      assert_equal [ "Larry Niven", "Jerry Pournelle" ], ShopView.build.works.sole.authors
    end
  end
end

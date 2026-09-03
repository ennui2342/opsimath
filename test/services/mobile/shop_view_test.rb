require "test_helper"

module Mobile
  class ShopViewTest < ActiveSupport::TestCase
    PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    def entries = ShopView.build.entries

    test "an owned work: one entry (kind work), owned true, with its owned editions and ISBNs" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel", original_publication_year: 1984)
      gibson = Contributor.create!(name: "William Gibson")
      WorkContributor.create!(work:, contributor: gibson, role: "author", display_order: 0)
      series = Series.create!(name: "Sprawl")
      WorkSeries.create!(work:, series:, position: 1)

      edition = Edition.create!(format: "paperback", format_detail: "mass_market", publisher: "Ace Books", publish_date: "1984")
      EditionContent.create!(work:, edition:)
      EditionIdentifier.create!(edition:, id_type: "isbn10", value: "0441569595")
      EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780441569595")
      EditionIdentifier.create!(edition:, id_type: "isfdb", value: "55210")
      EditionIdentifier.create!(edition:, id_type: "goodreads", value: "22623")
      edition.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")
      Copy.create!(edition:, disposition: "owned")

      entry = entries.sole
      assert_equal "work:#{work.id}", entry.id
      assert_equal "work", entry.kind
      assert_equal "Neuromancer", entry.title
      assert_equal [ "William Gibson" ], entry.authors
      assert_equal "Sprawl", entry.series
      assert_equal "1", entry.series_position
      assert entry.owned
      assert_not entry.wishlisted
      assert_nil entry.isbn13 # works carry ISBNs per-edition, not entry-level

      ed = entry.editions.sole
      assert_equal "paperback", ed.format
      assert_equal "Ace Books", ed.publisher
      assert_equal "1984", ed.year
      assert_equal "0441569595", ed.isbn10
      assert_equal "9780441569595", ed.isbn13
      assert_equal "55210", ed.isfdb
      assert_equal "22623", ed.goodreads
      assert ed.has_cover
    end

    test "a work with only a non-owned copy is excluded entirely" do
      work = Work.create!(title: "Sold Off", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "sold")

      assert_empty entries
    end

    test "only owned editions of an owned work appear as edition rows" do
      work = Work.create!(title: "Two Printings", literary_form: "novel")
      owned_ed = Edition.create!(publisher: "Gollancz")
      other_ed = Edition.create!(publisher: "Orbit")
      EditionContent.create!(work:, edition: owned_ed)
      EditionContent.create!(work:, edition: other_ed)
      Copy.create!(edition: owned_ed, disposition: "owned")
      Copy.create!(edition: other_ed, disposition: "given_away")

      assert_equal [ "Gollancz" ], entries.sole.editions.map(&:publisher)
    end

    test "a wishlisted work matched to a Work folds onto that work's entry" do
      work = Work.create!(title: "Wanted", literary_form: "novel")
      WishlistItem.create!(title: "Wanted", work:)

      entry = entries.sole
      assert_equal "work", entry.kind
      assert entry.wishlisted
      assert_not entry.owned
      assert_empty entry.editions
    end

    test "an unmatched wishlist entry becomes a kind-wishlist entry with ISBNs from external_ids" do
      WishlistItem.create!(
        title: "Vagabonds", author_name: "Hao Jingfang",
        external_ids: { "goodreads" => "49454725", "isbn10" => "1534422080", "isbn13" => "9781534422087" }
      )

      entry = entries.sole
      assert_equal "wishlist", entry.kind
      assert_equal "Vagabonds", entry.title
      assert_equal [ "Hao Jingfang" ], entry.authors
      assert entry.wishlisted
      assert_not entry.owned
      assert_equal "1534422080", entry.isbn10
      assert_equal "9781534422087", entry.isbn13
      assert_empty entry.editions
    end

    test "entries come back sorted by title, works and wishlist entries interleaved" do
      w = Work.create!(title: "Blindsight", literary_form: "novel")
      e = Edition.create!
      EditionContent.create!(work: w, edition: e)
      Copy.create!(edition: e, disposition: "owned")
      WishlistItem.create!(title: "Anathem")

      assert_equal [ "Anathem", "Blindsight" ], entries.map(&:title)
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

      assert_equal [ "Larry Niven", "Jerry Pournelle" ], entries.sole.authors
    end
  end
end

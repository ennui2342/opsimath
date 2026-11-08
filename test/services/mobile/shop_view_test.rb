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

      edition = Edition.create!(format: "paperback", format_detail: "mass_market", publisher: "Ace Books", publish_date: "1984", page_count: 271, cover_artist: "Bruce Pennington")
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
      assert_equal 271, ed.page_count
      assert_equal "owned", ed.disposition
      assert_equal "Bruce Pennington", ed.cover_artist
      assert_equal "tbr", ed.reading_status # no Reading yet
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

    test "every edition a copy passed through appears, owned first, each with its disposition" do
      work = Work.create!(title: "Two Printings", literary_form: "novel")
      retired_ed = Edition.create!(publisher: "Orbit")
      owned_ed = Edition.create!(publisher: "Gollancz")
      catalogue_only = Edition.create!(publisher: "Tor") # no copy — never surfaces
      [ retired_ed, owned_ed, catalogue_only ].each { |e| EditionContent.create!(work:, edition: e) }
      Copy.create!(edition: owned_ed, disposition: "owned")
      Copy.create!(edition: retired_ed, disposition: "replaced")

      eds = entries.sole.editions
      assert_equal [ "Gollancz", "Orbit" ], eds.map(&:publisher) # owned first
      assert_equal %w[owned replaced], eds.map(&:disposition)
    end

    test "reading_status is the book's, on every edition: open beats completed beats dnf; tbr only on an owned edition of an unread book" do
      book = lambda do |title, *statuses|
        work = Work.create!(title:, literary_form: "novel")
        [ "#{title} A", "#{title} B" ].each do |publisher|
          e = Edition.create!(publisher:)
          EditionContent.create!(work:, edition: e)
          Copy.create!(edition: e, disposition: "owned")
        end
        statuses.each { |s| Reading.create!(work:, edition: work.editions.first, status: s) }
      end
      book.("Reading", "completed", "reading")
      book.("Read", "completed", "dnf")
      book.("Dnf", "dnf")
      book.("Tbr")

      by_publisher = entries.flat_map(&:editions).index_by(&:publisher)
      assert_equal %w[reading reading], [ by_publisher["Reading A"].reading_status, by_publisher["Reading B"].reading_status ]
      assert_equal %w[read read], [ by_publisher["Read A"].reading_status, by_publisher["Read B"].reading_status ]
      assert_equal "dnf", by_publisher["Dnf B"].reading_status
      assert_equal "tbr", by_publisher["Tbr A"].reading_status
    end

    test "an edition read but not owned (a Copy-less unowned read) does not surface" do
      work = Work.create!(title: "Library Book", literary_form: "novel")
      owned_ed = Edition.create!(publisher: "Gollancz")
      library_ed = Edition.create!(publisher: "Orbit")
      EditionContent.create!(work:, edition: owned_ed)
      EditionContent.create!(work:, edition: library_ed)
      Copy.create!(edition: owned_ed, disposition: "owned")
      Reading.create!(work:, edition: library_ed, status: "completed", source: "library")

      assert_equal [ "Gollancz" ], entries.sole.editions.map(&:publisher)
    end

    test "a wanted book you also own — an upgrade hunt — is the owned work's entry, flagged wishlisted" do
      want = create_want(title: "Wanted")
      edition = Edition.create!(publisher: "Gollancz")
      EditionContent.create!(work: want.work, edition:)
      Copy.create!(edition:, disposition: "owned")

      entry = entries.sole
      assert_equal "work", entry.kind
      assert entry.wishlisted
      assert entry.owned
      assert_equal [ "Gollancz" ], entry.editions.map(&:publisher)
    end

    test "a wanted book you don't own is a kind-wishlist entry, scannable by the ISBN it was wanted under" do
      create_want(title: "Vagabonds", author: "Hao Jingfang", isbns: [ "9781534422087", "1534422080" ],
                  external_ids: { "goodreads" => "49454725" })

      entry = entries.sole
      assert_equal "wishlist", entry.kind
      assert_equal "Vagabonds", entry.title
      assert_equal [ "Hao Jingfang" ], entry.authors
      assert entry.wishlisted
      assert_not entry.owned
      assert_equal "1534422080", entry.isbn10
      assert_equal "9781534422087", entry.isbn13
      assert_equal "49454725", entry.goodreads
      assert_empty entry.editions
    end

    test "entries come back sorted by title, works and wishlist entries interleaved" do
      w = Work.create!(title: "Blindsight", literary_form: "novel")
      e = Edition.create!
      EditionContent.create!(work: w, edition: e)
      Copy.create!(edition: e, disposition: "owned")
      create_want(title: "Anathem")

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

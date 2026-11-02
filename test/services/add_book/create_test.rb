require "test_helper"

module AddBook
  class CreateTest < ActiveSupport::TestCase
    setup do
      stub_request(:get, %r{https://covers\.test/.*}).to_return(status: 200, body: File.binread(Rails.root.join("test/fixtures/files/cover.png")),
                                                               headers: { "Content-Type" => "image/png" })
      @found = { "title" => "Crossfire", "authors" => [ "Nancy Kress" ], "first_year" => 2003, "cover_url" => "https://covers.test/w.png",
                 "provider_works" => [ { "provider" => "isfdb", "id" => "1911", "isbns" => [ "9780765304674" ] },
                                       { "provider" => "openlibrary", "id" => "OL15842257W", "isbns" => [] } ] }
      @card = [ { "provider" => "isfdb", "id" => "55", "publisher" => "Tor", "publish_date" => "2003-12", "binding" => "hc",
                  "isbn13" => "9780765304674", "page_count" => 364, "cover_artist" => "John Harris", "cover_url" => "https://covers.test/55.png" },
                { "provider" => "openlibrary", "id" => "OL3565001M", "publisher" => "Tom Doherty Associates", "isbn10" => "0765304678",
                  "language" => "eng" } ]
    end

    test "want: a new work with its author, provider ids and a want seeded with ISBNs — no edition" do
      want = Create.want(work: nil, found: @found)

      work = want.work
      assert_equal [ "Crossfire", [ "Nancy Kress" ], 2003 ], [ work.title, work.authors.map(&:name), work.original_publication_year ]
      assert_equal [ [ "isfdb_title", "1911" ], [ "openlibrary_work", "OL15842257W" ] ], work.work_identifiers.order(:id_type).pluck(:id_type, :value)
      assert_equal [ "9780765304674" ], want.seed_isbns
      assert want.cover_image.attached?
      assert_empty work.editions
    end

    test "edition: filled from the card's ISFDB record; Open Library kept beside, filling only the gaps" do
      work, edition = Create.edition(work: nil, found: @found, card: @card)

      assert_equal [ "Tor", "2003-12", "hardcover", 364, "John Harris" ],
                   [ edition.publisher, edition.publish_date, edition.format, edition.page_count, edition.cover_artist ]
      assert_equal "isfdb", edition.field_sources["publisher"]
      assert edition.cover_image.attached?
      assert_equal %w[isfdb openlibrary], edition.enrichment_records.order(:provider).pluck(:provider)
      assert_equal "Tom Doherty Associates", edition.enrichment_records.find_by(provider: "openlibrary").fields["publisher"]
      assert_equal [ "eng", "openlibrary" ], [ edition.language, edition.field_sources["language"] ]
      ids = edition.edition_identifiers.pluck(:id_type, :value).to_h
      assert_equal({ "isbn13" => "9780765304674", "isbn10" => "0765304678", "isfdb" => "55", "openlibrary" => "OL3565001M" }, ids)
      assert edition.copies.sole.owned?
      assert_equal [ edition ], work.editions.to_a
      assert_equal 0, PendingDecision.count
    end

    test "a cover ISFDB doesn't have comes from Open Library" do
      @card.first.delete("cover_url")
      @card.last["cover_url"] = "https://covers.test/ol.png"

      _, edition = Create.edition(work: nil, found: @found, card: @card)

      assert edition.cover_image.attached?
      assert_equal "openlibrary", edition.field_sources["cover_image"]
      assert_equal 0, PendingDecision.count
    end

    test "edition with a reading: open, or finished with a date and rating" do
      work, edition = Create.edition(work: nil, found: @found, card: @card,
                                     reading: { status: "completed", date_finished: Date.new(2026, 11, 1), rating: "4" })

      reading = work.readings.sole
      assert_equal [ "completed", Date.new(2026, 11, 1), 4, edition, "owned_copy" ],
                   [ reading.status, reading.date_finished, reading.rating.to_i, reading.edition, reading.source ]
    end

    test "getting a wanted book: the edition goes onto the wanted work, and the want is retired" do
      want = create_want(title: "Crossfire", author: "Nancy Kress")

      work, = Create.edition(work: want.work, found: nil, card: @card)

      assert_equal want.work_id, work.id
      assert_not Want.exists?(want.id)
      assert Work.exists?(work.id)
    end

    test "a book read but not owned: no copy, and the reading isn't from your copy" do
      work, = Create.edition(work: nil, found: @found, card: @card, own: false, reading: { status: "reading", date_started: Date.current })

      assert_empty work.editions.first.copies
      assert_equal "other", work.readings.sole.source
    end
  end
end

require "test_helper"

module Providers
  class OpenLibraryTest < ActiveSupport::TestCase
    FIXTURES = Rails.root.join("test/fixtures/files/openlibrary")

    setup do
      @provider = OpenLibrary.new(client: ::OpenLibrary::Client.new(min_interval: 0))
    end

    def fixture(name) = { status: 200, body: FIXTURES.join(name).read, headers: { "Content-Type" => "application/json" } }

    test "known editions: the work found from an ISBN, then every edition, mapped (real Open Library data)" do
      stub_request(:get, "https://openlibrary.org/isbn/9780765304674.json").to_return(fixture("isbn_9780765304674.json"))
      stub_request(:get, "https://openlibrary.org/works/OL15842257W/editions.json?limit=500").to_return(fixture("editions_crossfire.json"))

      known = @provider.known_editions(isbns: [ "9780765304674" ])

      assert_equal [ "OL15842257W" ], known.work_ids
      assert_equal %w[OL25434832M OL3565001M OL24751832M], known.editions.map(&:id)
      german, tor, = known.editions
      assert_equal [ "Kontakt", "Bastei Lübbe", "Paperback", "ger", "2006", 477 ],
                   [ german.title, german.publisher, german.binding, german.language, german.publish_date, german.page_count ]
      assert_equal "https://covers.openlibrary.org/b/id/6754400-L.jpg", tor.cover_url
      assert_equal "9780765304674", tor.isbn # ISBN-10 only, folded
      assert_equal "openlibrary", tor.provider
    end

    test "known editions reuses the work key from a previous run, without an ISBN lookup" do
      stub_request(:get, "https://openlibrary.org/works/OL15842257W/editions.json?limit=500").to_return(fixture("editions_crossfire.json"))

      known = @provider.known_editions(isbns: [ "9780765304674" ], work_ids: [ "OL15842257W" ])

      assert_equal 3, known.editions.size
    end

    test "known editions follows every stored work id — Open Library keeps duplicate works for one book" do
      stub_request(:get, "https://openlibrary.org/works/OL15842257W/editions.json?limit=500").to_return(fixture("editions_crossfire.json"))
      stub_request(:get, "https://openlibrary.org/works/OL2W/editions.json?limit=500")
        .to_return(status: 200, body: { entries: [ { key: "/books/OL9M", title: "Crossfire" } ] }.to_json, headers: { "Content-Type" => "application/json" })

      known = @provider.known_editions(isbns: [], work_ids: %w[OL15842257W OL2W])

      assert_equal %w[OL15842257W OL2W], known.work_ids
      assert_equal 4, known.editions.size
    end

    test "known editions: no ISBN Open Library has means nothing, after a bounded number of tries" do
      isbns = %w[9780000000001 9780000000002 9780000000003 9780000000004]
      isbns.each { |i| stub_request(:get, "https://openlibrary.org/isbn/#{i}.json").to_return(status: 404) }

      known = @provider.known_editions(isbns:)

      assert_empty known.editions
      assert_not_requested :get, "https://openlibrary.org/isbn/9780000000004.json"
    end

    test "search gives one work per Open Library work — several for one book, as Open Library has them" do
      stub_request(:get, %r{openlibrary\.org/search\.json}).to_return(fixture("search_crossfire.json"))

      works = @provider.search_works(title: "Crossfire", author: "Nancy Kress")

      assert_equal %w[OL15842257W OL17728099W OL27441613W], works.map(&:id)
      assert_equal [ "Crossfire", [ "Nancy Kress" ] ], [ works.first.title, works.first.authors ]
      assert_nil works.first.editions
    end
  end
end

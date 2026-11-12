require "test_helper"

module Providers
  class IsfdbTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup { @provider = Isfdb.new(client: ::Isfdb::Client.new(base_url: BASE_URL)) }

    def json(body) = { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }

    def pub(pub_id, title_id, isbn13, overrides = {})
      { "_isfdb_pub_id" => pub_id, "_isfdb_title_id" => title_id, "isbn_13" => isbn13, "isbn_10" => "", "binding" => "pb",
        "publisher" => "Tor", "publish_date" => "2004-11", "title" => "Crossfire", "authors" => [ "Nancy Kress" ],
        "cover_url" => "https://covers.test/#{pub_id}.jpg|https://mirror.test/#{pub_id}.jpg", "cover_artists" => [ "John Harris" ] }.merge(overrides)
    end

    test "known editions: an anthology or nonfiction book has no printing list, so its own publication is taken" do
      stub_request(:get, "#{BASE_URL}/isbn/9780586052112/editions").to_return(status: 404, body: { detail: "isbn found but not linked to a book-type title" }.to_json)
      stub_request(:get, "#{BASE_URL}/isbn/9780586052112?all=true").to_return(json([ pub(118271, nil, "9780586052112", "title" => "The Way the Future Was", "publisher" => "Granada") ]))

      known = @provider.known_editions(isbns: [ "9780586052112" ])

      assert_empty known.work_ids
      assert_equal [ [ "118271", "Granada" ] ], known.editions.map { |e| [ e.id, e.publisher ] }
    end

    test "known editions: every edition, and the title id only from the work's own printings" do
      stub_request(:get, "#{BASE_URL}/isbn/9780765304674/editions").to_return(json([
        pub(1, 1911, "9780765304674"), pub(2, 5555, "9780000000002", "title" => "A Three-in-One Omnibus")
      ]))

      known = @provider.known_editions(isbns: [ "9780765304674" ])

      assert_equal [ "1911" ], known.work_ids
      assert_equal %w[1 2], known.editions.map(&:id)
      assert_equal [ "https://covers.test/1.jpg", "John Harris", "pb" ],
                   [ known.editions.first.cover_url, known.editions.first.cover_artist, known.editions.first.binding ]
    end

    test "search groups the adapter's editions back into works" do
      stub_request(:get, "#{BASE_URL}/search").with(query: hash_including("q" => "Crossfire Nancy Kress"))
        .to_return(json([ pub(1, 1911, "9780765304674", "publish_date" => "2003-12"), pub(2, 1911, "9780765343895"),
                          pub(9, 77, "9780000000009", "title" => "Crossfire Trail", "authors" => [ "Louis L'Amour" ]) ]))

      works = @provider.search_works(title: "Crossfire", author: "Nancy Kress")

      assert_equal %w[1911 77], works.map(&:id)
      assert_equal [ 2, 2003, "https://covers.test/1.jpg" ], [ works.first.edition_count, works.first.first_year, works.first.cover_url ]
    end
  test "known editions come by the linked titles too, not only an ISBN that may be another title's" do
      base = BASE_URL
      chapbook = { "_isfdb_pub_id" => 74123, "_isfdb_title_id" => 172997, "title" => "The Midwich Cuckoos", "isbn_13" => "9780237526894",
                   "publisher" => "Evans Brothers", "binding" => "tp" }
      novel = { "_isfdb_pub_id" => 5501, "_isfdb_title_id" => 7701, "title" => "The Midwich Cuckoos", "isbn_10" => "0140013083",
                "publisher" => "Penguin", "binding" => "pb", "publish_date" => "1960" }
      stub_request(:get, "#{base}/isbn/9780237526894/editions").to_return(status: 200, body: [ chapbook ].to_json)
      stub_request(:get, "#{base}/titles/7701/editions").to_return(status: 200, body: [ novel ].to_json)
      stub_request(:get, "#{base}/titles/172997/editions").to_return(status: 200, body: [ chapbook ].to_json)

      known = @provider.known_editions(isbns: [ "9780237526894" ], work_ids: %w[172997 7701])

      assert_equal %w[5501 74123], known.editions.map(&:id).sort
    end
  end
end

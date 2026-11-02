require "test_helper"

module OpenLibrary
  class ClientTest < ActiveSupport::TestCase
    setup { @client = Client.new(min_interval: 0) }

    def json(body) = { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }

    test "an ISBN lookup follows Open Library's redirect to the edition, with a descriptive User-Agent" do
      stub_request(:get, "https://openlibrary.org/isbn/9780765304674.json")
        .with(headers: { "User-Agent" => Client::USER_AGENT })
        .to_return(status: 302, headers: { "Location" => "https://openlibrary.org/books/OL3565001M.json" })
      stub_request(:get, "https://openlibrary.org/books/OL3565001M.json")
        .to_return(json("key" => "/books/OL3565001M", "works" => [ { "key" => "/works/OL15842257W" } ]))

      assert_equal "/works/OL15842257W", @client.isbn("9780765304674").dig("works", 0, "key")
    end

    test "an ISBN Open Library doesn't have is nil" do
      stub_request(:get, "https://openlibrary.org/isbn/9780000000002.json").to_return(status: 404)

      assert_nil @client.isbn("9780000000002")
    end

    test "editions follows pagination" do
      stub_request(:get, "https://openlibrary.org/works/OL1W/editions.json?limit=500")
        .to_return(json("entries" => [ { "key" => "/books/OL1M" } ], "links" => { "next" => "/works/OL1W/editions.json?limit=500&offset=500" }))
      stub_request(:get, "https://openlibrary.org/works/OL1W/editions.json?limit=500&offset=500")
        .to_return(json("entries" => [ { "key" => "/books/OL2M" } ], "links" => {}))

      assert_equal %w[/books/OL1M /books/OL2M], @client.editions("OL1W").map { |e| e["key"] }
    end

    test "a server error raises" do
      stub_request(:get, %r{openlibrary\.org/search\.json}).to_return(status: 503)

      assert_raises(ServiceError) { @client.search(title: "Crossfire") }
    end
  end
end

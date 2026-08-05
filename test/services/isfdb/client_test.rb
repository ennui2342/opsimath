require "test_helper"

module Isfdb
  class ClientTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
    end

    test "lookup_isbn returns the parsed response for a real shape" do
      # Real response, confirmed live against the actual adapter
      # (curl http://isfdb-adapter.k8s.ecafe.org:8080/isbn/0441172717)
      # after wiring up its Ingress.
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(
        status: 200,
        body: {
          provider: "isfdb", provider_display: "ISFDB", title: "Dune", subtitle: "",
          authors: [ "Frank Herbert" ], publisher: "Ace Books", publish_date: "2010",
          isbn_10: "0441172717", isbn_13: "9780441172719", description: "", cover_url: "",
          language: "eng", page_count: 883, categories: [], binding: "pb",
          _isfdb_pub_id: 426303, _isfdb_title_id: 2036, _isfdb_series_id: 869, _isfdb_series_num: 1
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = @client.lookup_isbn("0441172717")

      assert_equal "Dune", result["title"]
      assert_equal "Ace Books", result["publisher"]
      assert_equal "pb", result["binding"]
      assert_equal 426303, result["_isfdb_pub_id"]
    end

    test "lookup_isbn returns nil on a real 404 (not in the mirror)" do
      stub_request(:get, "#{BASE_URL}/isbn/0000000000").to_return(status: 404, body: { detail: "isbn not found" }.to_json)

      assert_nil @client.lookup_isbn("0000000000")
    end

    test "lookup_isbn raises on a 503 (mid-refresh database error)" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 503, body: { error: "database error" }.to_json)

      assert_raises(ServiceError) { @client.lookup_isbn("0441172717") }
    end
  end
end

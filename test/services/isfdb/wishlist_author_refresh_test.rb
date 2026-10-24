require "test_helper"

module Isfdb
  class WishlistAuthorRefreshTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
    end

    def item(author_name, **attrs)
      WishlistItem.create!(title: "A book", author_name:, **attrs)
    end

    def stub_search(name, results)
      stub_request(:get, "#{BASE_URL}/authors/search").with(query: { q: name, limit: 200 })
        .to_return(status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_author(id, died_date)
      stub_request(:get, "#{BASE_URL}/authors/#{id}").with(query: { works: false })
        .to_return(status: 200, body: { external_id: id.to_s, died_date: }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    test "records a dead author's death date, matching the name case-insensitively" do
      vance = item("Jack vance")
      stub_search("vance", [ { "external_id" => "7", "name" => "Jack Vance" }, { "external_id" => "8", "name" => "Jack Vance Jr." } ])
      stub_author(7, "2013-05-26")

      WishlistAuthorRefresh.run(client: @client)

      vance.reload
      assert_equal [ 7, "2013-05-26", :dead ], [ vance.author_isfdb_id, vance.author_died_date, vance.author_status ]
    end

    test "several records with the same name: the oldest is the main one" do
      le_guin = item("Ursula K. Le Guin")
      stub_search("Guin", [ { "external_id" => "229311", "name" => "Ursula K. LeGuin" },
                              { "external_id" => "37", "name" => "Ursula K. Le Guin" } ])
      stub_author(37, "2018-01-22")

      WishlistAuthorRefresh.run(client: @client)

      assert_equal [ 37, :dead ], [ le_guin.reload.author_isfdb_id, le_guin.author_status ]
    end

    test "a living author has an id and no death date" do
      lee = item("Yoon Ha Lee")
      stub_search("Lee", [ { "external_id" => "9", "name" => "Yoon Ha Lee" } ])
      stub_author(9, nil)

      WishlistAuthorRefresh.run(client: @client)

      assert_equal :living, lee.reload.author_status
    end

    test "no exact match leaves the author unknown, but checked" do
      kim = item("Kim Bo-young")
      stub_search("Bo-young", [ { "external_id" => "10", "name" => "Kim Bo-young (translator)" } ])
      stub_search("Kim Bo-young", [])

      WishlistAuthorRefresh.run(client: @client)

      kim.reload
      assert_equal :unknown, kim.author_status
      assert_not_nil kim.author_checked_at
    end

    test "each distinct author is looked up once per run" do
      a, b = item("Tanith Lee"), item("Tanith Lee")
      stub_search("Lee", [ { "external_id" => "105", "name" => "Tanith Lee" } ])
      stub_author(105, "2015-05-24")

      WishlistAuthorRefresh.run(client: @client)

      assert_requested :get, "#{BASE_URL}/authors/105?works=false", times: 1
      assert_equal [ :dead, :dead ], [ a.reload.author_status, b.reload.author_status ]
    end

    test "searches on the surname, so differently-punctuated initials still match" do
      ballard = item("J.G. Ballard")
      stub_search("Ballard", [ { "external_id" => "11", "name" => "J. G. Ballard" }, { "external_id" => "12", "name" => "Ballard Jones" } ])
      stub_author(11, "2009-04-19")

      WishlistAuthorRefresh.run(client: @client)

      assert_equal :dead, ballard.reload.author_status
    end

    test "a non-ASCII name is searched on an ASCII word and matched in full" do
      lem = item("Stanisław Lem")
      stub_search("Lem", [ { "external_id" => "13", "name" => "Stanisław Lem" }, { "external_id" => "14", "name" => "Clement Lem" } ])
      stub_author(13, "2006-03-27")

      WishlistAuthorRefresh.run(client: @client)

      assert_equal :dead, lem.reload.author_status
    end

    test "falls back to the full name when the surname search doesn't find the author" do
      taylor = item("Dennis E. Taylor")
      stub_search("Taylor", [ { "external_id" => "1", "name" => "Ann Taylor" } ])
      stub_search("Dennis E. Taylor", [ { "external_id" => "20", "name" => "Dennis E. Taylor" } ])
      stub_author(20, nil)

      WishlistAuthorRefresh.run(client: @client)

      assert_equal :living, taylor.reload.author_status
    end

    test "a Jr. suffix isn't taken for the surname" do
      vonnegut = item("Kurt Vonnegut Jr.")
      stub_search("Vonnegut", [ { "external_id" => "21", "name" => "Kurt Vonnegut, Jr." } ])
      stub_author(21, "2007-04-11")

      WishlistAuthorRefresh.run(client: @client)

      assert_equal :dead, vonnegut.reload.author_status
    end

    test "skips items checked within the month" do
      item("Tanith Lee", author_checked_at: 1.week.ago)

      result = WishlistAuthorRefresh.run(client: @client) # no stubs — a request would raise

      assert_equal 0, result.stale
    end

    test "an adapter failure leaves the item unchecked for the next run" do
      lee = item("Tanith Lee")
      stub_request(:get, "#{BASE_URL}/authors/search").with(query: hash_including({})).to_return(status: 503)

      WishlistAuthorRefresh.run(client: @client)

      assert_nil lee.reload.author_checked_at
    end
  end
end

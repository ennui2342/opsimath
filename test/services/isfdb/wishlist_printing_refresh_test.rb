require "test_helper"

module Isfdb
  class WishlistPrintingRefreshTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
      @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee",
                                   external_ids: { "goodreads" => "1", "isbn13" => "9780860079425", "isbn10" => "0860079422" })
    end

    def stub_editions(isbn, body, status: 200)
      stub_request(:get, "#{BASE_URL}/isbn/#{isbn}/editions")
        .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def edition(pub_id, binding, overrides = {})
      { "_isfdb_pub_id" => pub_id, "binding" => binding, "publisher" => "Orbit", "publish_date" => "1977-09",
        "isbn_10" => "0860079422", "isbn_13" => "", "cover_artists" => [ "Les Edwards" ],
        "cover_url" => "https://example.test/#{pub_id}.jpg" }.merge(overrides)
    end

    test "caches the physical printings, dropping ebook and audio" do
      stub_editions("9780860079425", [
        edition(1, "pb"), edition(2, "hc"), edition(3, "ebook"),
        edition(4, "audio CD"), edition(5, "digital audio download"), edition(6, "dos")
      ])

      result = WishlistPrintingRefresh.run(client: @client)

      assert_equal [ 1, 2, 6 ], @item.wishlist_printings.order(:isfdb_pub_id).pluck(:isfdb_pub_id)
      pb = @item.wishlist_printings.find_by(isfdb_pub_id: 1)
      assert_equal [ "0860079422", nil, "Les Edwards" ], [ pb.isbn10, pb.isbn13, pb.cover_artist ]
      assert_not_nil @item.reload.printings_refreshed_at
      assert_equal 1, result.refreshed
    end

    test "falls back to the ISBN-10 when ISFDB doesn't know the ISBN-13" do
      stub_editions("9780860079425", [], status: 404)
      stub_editions("0860079422", [ edition(1, "pb") ])

      WishlistPrintingRefresh.run(client: @client)

      assert_equal 1, @item.wishlist_printings.count
    end

    test "a refresh keeps a printing's row id, updates it, and drops vanished printings" do
      kept = @item.wishlist_printings.create!(isfdb_pub_id: 1, binding: "pb", publisher: "Old name")
      @item.wishlist_printings.create!(isfdb_pub_id: 99, binding: "pb")
      stub_editions("9780860079425", [ edition(1, "pb") ])

      WishlistPrintingRefresh.run(client: @client)

      assert_equal [ kept.id ], @item.wishlist_printings.pluck(:id)
      assert_equal "Orbit", kept.reload.publisher
    end

    test "resolves publishers through the authority file" do
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Orbit")
      term.register_variant("Futura / Orbit")
      stub_editions("9780860079425", [ edition(1, "pb", "publisher" => "Futura / Orbit") ])

      WishlistPrintingRefresh.run(client: @client)

      assert_equal "Orbit", @item.wishlist_printings.first.publisher
    end

    test "skips items refreshed within the last week" do
      @item.update!(printings_refreshed_at: 1.day.ago)

      result = WishlistPrintingRefresh.run(client: @client) # no stubs — a request would raise

      assert_equal 0, result.stale
    end

    test "an item ISFDB doesn't know is marked refreshed with no printings" do
      stub_editions("9780860079425", [], status: 404)
      stub_editions("0860079422", [], status: 404)

      WishlistPrintingRefresh.run(client: @client)

      assert_empty @item.wishlist_printings
      assert_not_nil @item.reload.printings_refreshed_at
    end

    test "an adapter failure leaves the item stale for the next run" do
      stub_editions("9780860079425", {}, status: 503)

      result = WishlistPrintingRefresh.run(client: @client)

      assert_equal 0, result.refreshed
      assert_nil @item.reload.printings_refreshed_at
    end
  end
end

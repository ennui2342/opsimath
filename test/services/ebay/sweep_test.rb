require "test_helper"

module Ebay
  class SweepTest < ActiveSupport::TestCase
    class FakeClient
      attr_reader :calls

      def initialize(by_query) = (@by_query = by_query; @calls = [])

      def search(**params)
        @calls << params
        @by_query.fetch(params[:gtin] || params[:q], [])
      end
    end

    setup do
      @profile = CollectingProfile.new(recent_years: 5, favourite_artist_min_owned: 5)
      @item = WishlistItem.create!(title: "Hello Summer, Goodbye", author_name: "Michael G. Coney",
                                   external_ids: { "isbn10" => "0575019743" })
      @item.wishlist_printings.create!(isfdb_pub_id: 1, binding: "pb", publish_date: "1978-04", publisher: "Pan Books")
    end

    def summary(id, title, price: "4.99", **extra)
      { "itemId" => id, "title" => title, "itemWebUrl" => "https://ebay.test/#{id}",
        "price" => { "value" => price, "currency" => "GBP" }, "buyingOptions" => [ "FIXED_PRICE" ],
        "condition" => "Good", "itemLocation" => { "country" => "GB" },
        "shippingOptions" => [ { "shippingCostType" => "FIXED", "shippingCost" => { "value" => "2.70" } } ] }.merge(extra)
    end

    def sweep(client, now: Time.current) = Sweep.new(client:, profile: @profile, now:).run

    test "searches by keyword (UK, cheapest first) and by the wishlisted ISBN, recording relevant listings" do
      client = FakeClient.new(
        "Hello Summer, Goodbye Michael G. Coney" => [
          summary("1", "Hello Summer, Goodbye - Michael Coney - Pan 1978"),
          summary("2", "Job lot 10 sci-fi books inc Hello Summer Goodbye Coney"),
          summary("3", "Hello Summer Goodbye by Lisa Smith (romance)"),
          summary("5", "York Notes: Hello Summer, Goodbye (Michael Coney) study guide")
        ],
        "9780575019744" => [ summary("1", "Hello Summer, Goodbye - Michael Coney - Pan 1978"), summary("4", "Coney: Hello Summer, Goodbye", price: "30.00") ]
      )

      result = sweep(client)

      assert_equal({ category_ids: "267", filter: "itemLocationCountry:GB", sort: "price" },
                   client.calls.first.slice(:category_ids, :filter, :sort))
      assert_equal %w[1 4], @item.ebay_listings.order(:ebay_item_id).pluck(:ebay_item_id)
      listing = @item.ebay_listings.find_by(ebay_item_id: "1")
      assert_equal [ 499, 270, "keyword", 769 ], [ listing.price, listing.shipping, listing.found_by, listing.total ]
      assert_equal "gtin", @item.ebay_listings.find_by(ebay_item_id: "4").found_by
      assert_equal 2, result.created
    end

    test "books the profile doesn't hunt are never searched" do
      @item.wishlist_printings.delete_all
      @item.update!(author_isfdb_id: 9, author_died_date: nil) # living author, no A-format: buy new
      client = FakeClient.new({})

      assert_equal 0, sweep(client).hunted
      assert_empty client.calls
    end

    test "a listing seen again is updated, not duplicated; one unseen for a week is ended" do
      client = FakeClient.new("Hello Summer, Goodbye Michael G. Coney" => [ summary("1", "Hello Summer, Goodbye Coney", price: "6.00") ])
      sweep(client, now: 10.days.ago)
      stale = @item.ebay_listings.create!(ebay_item_id: "old", title: "x", found_by: "keyword", first_seen_at: 10.days.ago, last_seen_at: 10.days.ago)

      sweep(client)

      listing = @item.ebay_listings.find_by(ebay_item_id: "1")
      assert_equal 600, listing.price
      assert listing.first_seen_at < 9.days.ago
      assert_nil listing.ended_at
      assert_not_nil stale.reload.ended_at
    end

    test "an auction past its end time is ended" do
      ended = @item.ebay_listings.create!(ebay_item_id: "a", title: "x", found_by: "keyword", buying_options: [ "AUCTION" ],
                                          auction_ends_at: 1.hour.ago, first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)

      sweep(FakeClient.new({}))

      assert_not_nil ended.reload.ended_at
    end
  end
end

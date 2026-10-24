require "test_helper"

module Ebay
  class PrintingIdentifierTest < ActiveSupport::TestCase
    # Scores by the cover image's bytes, which the stubbed downloads set
    # to the cover URL's last path segment.
    class FakeCompare
      def initialize(scores) = @scores = scores

      def compare(_photo, cover)
        ratio, inliers = @scores.fetch(cover, [ 0.0, 0 ])
        Enrichment::CoverCompareClient::Result.new(ratio:, inliers:)
      end
    end

    setup do
      stub_request(:get, %r{https://covers\.test/.*}).to_return { |req| { status: 200, body: req.uri.path.split("/").last } }
      @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee")
      @orbit77 = printing(1, "1977-09", "Orbit", "0860079422", "orbit77")
      @orbit79 = printing(2, "1979", "Orbit", "0860079422", "orbit7985")
      @orbit85 = printing(3, "1985", "Orbit", "0860079422", "orbit7985")
      @daw = printing(4, "1975-06", "DAW Books", "0879971770", "daw")
    end

    def printing(pub_id, date, publisher, isbn10, cover)
      @item.wishlist_printings.create!(isfdb_pub_id: pub_id, binding: "pb", publish_date: date, publisher:,
                                       isbn10:, cover_url: "https://covers.test/#{cover}")
    end

    def listing(title)
      @item.ebay_listings.create!(ebay_item_id: SecureRandom.hex(4), title:, image_url: "https://covers.test/photo",
                                  found_by: "keyword", first_seen_at: Time.current, last_seen_at: Time.current)
    end

    def identify(listing, scores) = PrintingIdentifier.new(compare: FakeCompare.new(scores)).identify(listing)

    test "the cover match wins over the ISBN in the title" do
      l = listing("The Birthgrave Tanith Lee 0860079422 Orbit 1985")

      assert_equal "cover", identify(l, "orbit7985" => [ 0.25, 500 ], "orbit77" => [ 0.003, 5 ])
      assert_equal [ 2, 3 ], l.reload.matched_pub_ids.sort
      assert_in_delta 0.25, l.cover_scores["2"]["ratio"]
    end

    test "text narrows a shared-cover group when it can" do
      l = listing("The Birthgrave - Orbit 1979 paperback")

      identify(l, "orbit7985" => [ 0.25, 500 ])

      assert_equal [ 2 ], l.reload.matched_pub_ids
    end

    test "no cover match: an ISBN in the title gives every printing sharing it" do
      l = listing("Birthgrave Tanith Lee ISBN 0860079422")

      assert_equal "text", identify(l, {})
      assert_equal [ 1, 2, 3 ], l.reload.matched_pub_ids.sort
    end

    test "no cover match: publisher and year pin one printing; the publisher must be a whole word" do
      l = listing("Tanith Lee The Birthgrave DAW 1975 1st printing")
      assert_equal "text", identify(l, {})
      assert_equal [ 4 ], l.reload.matched_pub_ids

      unrelated = listing("The Birthgrave Tanith Lee Orbiting Press 1977")
      assert_equal "unknown", identify(unrelated, {})
    end

    test "a weak cover score is no match" do
      l = listing("The Birthgrave Tanith Lee paperback")

      assert_equal "unknown", identify(l, "daw" => [ 0.05, 100 ], "orbit77" => [ 0.2, 12 ])
      assert_empty l.reload.matched_pub_ids
    end

    test "run identifies live, unidentified listings, cheapest first, up to the limit" do
      cheap = listing("The Birthgrave")
      cheap.update!(price: 300)
      dear = listing("The Birthgrave")
      dear.update!(price: 900)

      stub_request(:post, %r{/compare}).to_return(status: 200, body: { ratio: 0.0, inliers: 0 }.to_json)
      result = PrintingIdentifier.run(limit: 1)

      assert_equal 1, result.identified
      assert_equal "unknown", cheap.reload.identified_by
      assert_nil dear.reload.identified_by
    end
  end
end

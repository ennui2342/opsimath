require "test_helper"

module Ui
  class CoverChoiceCardComponentTest < ViewComponent::TestCase
    Listing = Struct.new(:url, :price, :current_bid, :shipping, :condition, :auction_ends_at, :total, keyword_init: true) do
      def auction? = !auction_ends_at.nil?
    end

    def cover(**attrs)
      printings = [ WishlistPrinting.new(isfdb_pub_id: 2, publisher: "Orbit", publish_date: "1979", binding: "pb",
                                         cover_url: "https://covers.test/2.jpg"),
                    WishlistPrinting.new(isfdb_pub_id: 3, publisher: "Orbit", publish_date: "1985", binding: "pb") ]
      WishlistItemView::Cover.new({ id: 2, printings:, artists: [ "Peter Jones" ], favourite: true, chosen: true, listings: [] }.merge(attrs))
    end

    test "shows the artist with a favourite star, the printings, and a checked box for a chosen cover" do
      render_inline(CoverChoiceCardComponent.new(cover: cover))

      assert_text "★"
      assert_text "Peter Jones"
      assert_text "Orbit 1979, 1985"
      assert_selector "input[type=checkbox][name='covers[]'][value='2'][checked]"
      assert_selector "img[src='https://covers.test/2.jpg']"
      assert_text "No listings on this cover"
    end

    test "an unchosen cover is unchecked and has no star when the artist isn't a favourite" do
      render_inline(CoverChoiceCardComponent.new(cover: cover(chosen: false, favourite: false)))

      assert_no_text "★"
      assert_selector "input[type=checkbox]:not([checked])"
    end

    test "lists the cheapest listings with postage, and counts the rest" do
      listings = Array.new(5) do |i|
        Listing.new(url: "https://ebay.test/#{i}", price: 400 + i, shipping: 270, condition: "Good", total: 670 + i)
      end
      listings[0].auction_ends_at = Time.zone.parse("2026-10-28 19:46")
      listings[0].current_bid = 99

      render_inline(CoverChoiceCardComponent.new(cover: cover(listings:)))

      assert_link "£0.99 + £2.70 · Good · auction, ends 28 Oct", href: "https://ebay.test/0"
      assert_link "£4.01 + £2.70 · Good", href: "https://ebay.test/1"
      assert_text "+ 2 more"
    end
  end
end

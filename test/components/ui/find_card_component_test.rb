require "test_helper"

module Ui
  class FindCardComponentTest < ViewComponent::TestCase
    setup do
      @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", target_price: 900)
      printing = WishlistPrinting.new(isfdb_pub_id: 2, publisher: "Orbit", publish_date: "1979", binding: "pb",
                                      cover_url: "https://covers.test/2.jpg")
      @cover = WishlistItemView::Cover.new(id: 2, printings: [ printing ], artists: [ "Peter Jones" ], favourite: true,
                                           chosen: true, listings: [])
      now = Time.current
      @listing = @item.ebay_listings.create!(ebay_item_id: "x", title: "Tanith Lee The Birthgrave Orbit pb", url: "https://ebay.test/x",
                                             image_url: "https://ebay.test/x.jpg", price: 450, shipping: 270, condition: "Good",
                                             found_by: "keyword", first_seen_at: now, last_seen_at: now)
    end

    def find(**attrs) = Finds::Find.new({ listing: @listing, item: @item, cover: @cover, median: 1500, count: 6, reason: :spread }.merge(attrs))

    test "shows the eBay photo beside the matched cover, the price, and why it's a find" do
      render_inline(FindCardComponent.new(find: find))

      assert_selector "img[src='https://ebay.test/x.jpg']"
      assert_selector "img[src='https://covers.test/2.jpg']"
      assert_text "★"
      assert_text "£4.50 + £2.70 postage · Good"
      assert_text "48% of the £15.00 median across 6 listings of this cover"
      assert_selector "article#ebay_listing_#{@listing.id}"
    end

    test "a target-price find says so" do
      render_inline(FindCardComponent.new(find: find(reason: :target)))

      assert_text "At or under your £9.00 target"
    end
  end
end

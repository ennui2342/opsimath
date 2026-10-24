module Ui
  class CoverChoiceCardComponentPreview < ViewComponent::Preview
    Listing = Struct.new(:url, :price, :current_bid, :shipping, :condition, :auction_ends_at, :total, keyword_init: true) do
      def auction? = !auction_ends_at.nil?
      def link = url
    end

    def chosen_favourite
      render(CoverChoiceCardComponent.new(cover: cover(chosen: true, favourite: true, listings: [
        Listing.new(url: "#", price: 450, shipping: 270, condition: "Good", total: 720),
        Listing.new(url: "#", price: 1294, current_bid: 866, shipping: 338, condition: "Very Good",
                    auction_ends_at: 4.days.from_now, total: 1204)
      ])))
    end

    def not_chosen_no_listings
      render(CoverChoiceCardComponent.new(cover: cover(chosen: false, favourite: false, listings: [])))
    end

    private

    def cover(**attrs)
      printings = [ WishlistPrinting.new(isfdb_pub_id: 2, publisher: "Orbit", publish_date: "1979", binding: "pb",
                                         cover_url: "https://www.isfdb.org/wiki/images/2/2b/BRTHGRVRB1979.jpg"),
                    WishlistPrinting.new(isfdb_pub_id: 3, publisher: "Orbit", publish_date: "1985", binding: "pb") ]
      WishlistItemView::Cover.new(id: 2, printings:, artists: [ "Peter Jones" ], **attrs)
    end
  end
end

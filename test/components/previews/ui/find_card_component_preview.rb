module Ui
  class FindCardComponentPreview < ViewComponent::Preview
    Listing = Struct.new(:id, :title, :url, :image_url, :price, :current_bid, :shipping, :condition,
                         :auction_ends_at, :bid_count, :total, keyword_init: true) do
      def auction? = !auction_ends_at.nil?
      def to_key = [ id ]
      def model_name = EbayListing.model_name
      def persisted? = true
      def to_param = id.to_s
    end

    def spread_find
      render(FindCardComponent.new(find: find(reason: :spread)))
    end

    def target_find_auction
      render(FindCardComponent.new(find: find(reason: :target, auction_ends_at: 2.days.from_now, current_bid: 420, bid_count: 2)))
    end

    private

    def find(reason:, **listing_attrs)
      item = WishlistItem.new(id: 1, title: "The Birthgrave", author_name: "Tanith Lee", target_price: 900)
      printing = WishlistPrinting.new(isfdb_pub_id: 2, publisher: "Orbit", publish_date: "1979", binding: "pb",
                                      cover_url: "https://www.isfdb.org/wiki/images/2/2b/BRTHGRVRB1979.jpg")
      cover = WishlistItemView::Cover.new(id: 2, printings: [ printing ], artists: [ "Peter Jones" ], favourite: true, chosen: true, listings: [])
      listing = Listing.new({ id: 1, title: "Tanith Lee The Birthgrave Orbit 1979 paperback", url: "#", image_url: nil,
                              price: 450, shipping: 270, condition: "Good", total: 720 }.merge(listing_attrs))
      Finds::Find.new(listing:, item:, cover:, median: 1500, count: 6, reason:)
    end
  end
end

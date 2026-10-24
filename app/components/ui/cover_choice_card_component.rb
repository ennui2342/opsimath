module Ui
  # One cover in the wishlist cover picker (docs/BARGAIN_HUNTING.md, "Front
  # end"): the ISFDB cover image, its artist (★ when a favourite), the
  # printings that used it, a "want" checkbox, and its cheapest live eBay
  # listings. Phone-first: the cover sits on top, a grid of these wraps
  # two-up on a phone.
  #
  # Takes a WishlistItemView::Cover — or anything with the same readers.
  class CoverChoiceCardComponent < ApplicationComponent
    LISTINGS_SHOWN = 3

    def initialize(cover:, field_name: "covers[]")
      @cover = cover
      @field_name = field_name
    end

    attr_reader :cover, :field_name

    def artist_line
      cover.artists.any? ? cover.artists.join(", ") : "Artist unknown"
    end

    def shown_listings = cover.listings.first(LISTINGS_SHOWN)

    def more_listings = [ cover.listings.size - LISTINGS_SHOWN, 0 ].max

    def card_classes
      base = "flex flex-col overflow-hidden rounded-lg border"
      if cover.chosen
        "#{base} border-green-600 ring-1 ring-green-600 dark:border-green-500 dark:ring-green-500"
      else
        "#{base} border-gray-200 opacity-75 dark:border-gray-800"
      end
    end

    def price(pence) = pence ? format("£%.2f", pence / 100.0) : "?"

    # "£4.20 + £2.70 · Good · auction, ends 28 Oct"
    def listing_line(listing)
      cost = listing.auction? && listing.current_bid ? listing.current_bid : listing.price
      parts = [ listing.shipping ? "#{price(cost)} + #{price(listing.shipping)}" : price(cost), listing.condition ]
      parts << "auction, ends #{listing.auction_ends_at.strftime('%-d %b')}" if listing.auction? && listing.auction_ends_at
      parts.compact.join(" · ")
    end
  end
end

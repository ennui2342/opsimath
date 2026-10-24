module Ui
  # One eBay find on the Finds queue (docs/BARGAIN_HUNTING.md, "/finds"):
  # the listing's own photo beside the ISFDB cover it was identified as —
  # so a wrong match shows at a glance — then the book, the cover's
  # artist (★ when a favourite), price with postage, why it's a find, and
  # the two actions: Dismiss (Turbo Stream, removes the card in place)
  # and Wrong printing.
  #
  # Takes a Finds::Find.
  class FindCardComponent < ApplicationComponent
    def initialize(find:)
      @find = find
    end

    attr_reader :find

    def listing = find.listing

    def price(pence) = pence ? format("£%.2f", pence / 100.0) : "?"

    def price_line
      cost = listing.auction? && listing.current_bid ? listing.current_bid : listing.price
      parts = [ listing.shipping ? "#{price(cost)} + #{price(listing.shipping)} postage" : "#{price(cost)} (postage unknown)" ]
      parts << listing.condition if listing.condition
      parts << "auction, #{listing.bid_count.to_i} bids, ends #{listing.auction_ends_at.strftime('%-d %b %H:%M')}" if listing.auction? && listing.auction_ends_at
      parts.join(" · ")
    end

    def reason_line
      if find.reason == :target
        "At or under your #{price(find.item.target_price)} target"
      else
        "#{(find.ratio * 100).round}% of the #{price(find.median.round)} median across #{find.count} listings of this cover"
      end
    end

    def artist_line = find.cover.artists.any? ? find.cover.artists.join(", ") : "Artist unknown"
  end
end

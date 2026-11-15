module Ui
  # One eBay find on the Finds queue (docs/BARGAIN_HUNTING.md, "/finds"):
  # the listing's own photo beside the ISFDB cover it was identified as —
  # so a wrong match shows at a glance — then the book, the cover's
  # artist (★ when a favourite), price with postage, why it's a find, and
  # the actions: Dismiss (this copy; Turbo Stream, swaps the card for an
  # undo), Not this cover (the cover leaves the book's chosen covers, and
  # every find on it goes) and Wrong printing.
  #
  # Takes a Finds::Find.
  class FindCardComponent < ApplicationComponent
    # `same_seller`: how many other finds on the page are from this seller.
    def initialize(find:, same_seller: 0)
      @find = find
      @same_seller = same_seller
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
        "At or under your #{price(find.want.target_price)} target"
      else
        "#{(find.ratio * 100).round}% of the #{price(find.median.round)} median across #{find.count} listings of this cover"
      end
    end

    # "Seller: bookfinder_uk (99.8%, 1,234)" and how many more finds are
    # theirs — Mark combines purchases from one seller for postage.
    def seller_line
      return unless listing.seller

      feedback = [ ("#{listing.seller_feedback_percentage}%" if listing.seller_feedback_percentage),
                   (helpers.number_with_delimiter(listing.seller_feedback_score) if listing.seller_feedback_score) ].compact.join(", ")
      safe_join([ "Seller: ", link_to(listing.seller, "https://www.ebay.co.uk/usr/#{ERB::Util.url_encode(listing.seller)}", target: "_blank", rel: "noopener", class: "hover:underline"),
                  (" (#{feedback})" if feedback.present?),
                  (" · #{@same_seller} more #{'find'.pluralize(@same_seller)} from this seller" if @same_seller.positive?) ].compact)
    end

    def artist_line = find.cover.artists.any? ? find.cover.artists.join(", ") : "Artist unknown"
  end
end

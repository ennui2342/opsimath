# The eBay listings worth acting on (docs/BARGAIN_HUNTING.md, "Judging a
# bargain"): live, not dismissed, on a cover Mark wants, and either
#
# - at or under the book's target price, or
# - well below the median of the *same cover's* live listings — prices
#   are compared per cover, never per book, since a reprint is usually
#   the cheapest copy of anything.
#
# Only a cover's cheapest listing can be a spread find: several bulk
# sellers at the same low price are that cover's going rate, not several
# bargains. Covers with too few listings can't be judged by spread;
# they're still on the book page. Favourite artists' covers sort first. Thresholds are
# provisional until there's price history to set them from.
class Finds
  SPREAD = 0.6
  MIN_LISTINGS = 3

  Find = Struct.new(:listing, :item, :cover, :median, :count, :reason, keyword_init: true) do
    def favourite? = cover.favourite

    def ratio = median&.positive? ? listing.total.to_f / median : nil
  end

  def self.all(profile: CollectingProfile.current)
    WishlistItem.includes(:wishlist_printings, :ebay_listings).flat_map do |item|
      WishlistItemView.new(item, profile:).covers.select(&:chosen).flat_map { |cover| for_cover(item, cover) }
    end.sort_by { |f| [ f.reason == :target ? 0 : 1, f.favourite? ? 0 : 1, f.ratio || 0, f.listing.total ] }
  end

  def self.for_cover(item, cover)
    priced = cover.listings.select(&:total)
    median = median(priced.map(&:total))
    cheapest = priced.min_by(&:total)
    priced.filter_map do |listing|
      reason =
        if item.target_price && listing.total <= item.target_price then :target
        elsif listing == cheapest && priced.size >= MIN_LISTINGS && listing.total <= SPREAD * median then :spread
        end
      reason && Find.new(listing:, item:, cover:, median:, count: priced.size, reason:)
    end
  end

  def self.median(values)
    return if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end

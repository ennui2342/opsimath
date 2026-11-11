# The eBay listings worth acting on (docs/BARGAIN_HUNTING.md, "Judging a
# bargain"): live, not dismissed, on a cover Mark wants, and
#
# - for a book with a target price: at or under it — the target is what
#   he'll pay, so it's the only test (a £35 copy at 41% of the usual £87
#   was still a find under a £10 target, 2026-11-11);
# - otherwise: well below the median of the *same cover's* live listings
#   — prices are compared per cover, never per book, since a reprint is
#   usually the cheapest copy of anything.
#
# Only a cover's cheapest listing can be a spread find: several bulk
# sellers at the same low price are that cover's going rate, not several
# bargains. A dismissed listing is never a find, but its price still
# counts towards the cover's median and listing count — dismissing one
# says "not that copy", not that the market changed; the cheapest copy
# Mark hasn't dismissed can still be a find. Covers with too few listings can't be judged by spread;
# they're still on the book page. Favourite artists' covers sort first. Thresholds are
# provisional until there's price history to set them from.
class Finds
  SPREAD = 0.6
  MIN_LISTINGS = 3

  Find = Struct.new(:listing, :want, :cover, :median, :count, :reason, keyword_init: true) do
    def favourite? = cover.favourite

    def ratio = median&.positive? ? listing.total.to_f / median : nil
  end

  def self.all(profile: CollectingProfile.current)
    Want.includes(work: [ :provider_editions, :ebay_listings, { work_contributors: :contributor } ]).flat_map do |want|
      WishlistItemView.new(want, profile:).covers.select(&:chosen).flat_map { |cover| for_cover(want, cover) }
    end.sort_by { |f| [ f.reason == :target ? 0 : 1, f.favourite? ? 0 : 1, f.ratio || 0, f.listing.total ] }
  end

  def self.for_cover(want, cover)
    market = cover.priced.select(&:total)
    median = median(market.map(&:total))
    candidates = cover.listings.select(&:total)
    cheapest = candidates.min_by(&:total)
    candidates.filter_map do |listing|
      reason =
        if want.target_price then (:target if listing.total <= want.target_price)
        elsif listing == cheapest && market.size >= MIN_LISTINGS && listing.total <= SPREAD * median then :spread
        end
      reason && Find.new(listing:, want:, cover:, median:, count: market.size, reason:)
    end
  end

  def self.median(values)
    return if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end

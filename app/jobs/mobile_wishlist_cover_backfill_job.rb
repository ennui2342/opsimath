# Wraps Mobile::WishlistCoverBackfill for `rake mobile:backfill_wishlist_covers`.
# Not scheduled — a one-off catch-up for wishlist items that predate cover
# capture (docs/MOBILE.md).
class MobileWishlistCoverBackfillJob < ApplicationJob
  queue_as :default

  def perform
    result = Mobile::WishlistCoverBackfill.run
    Rails.logger.info("wishlist cover backfill: #{result}")
    result
  end
end

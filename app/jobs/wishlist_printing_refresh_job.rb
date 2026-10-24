# Keeps WishlistPrinting current — the ISFDB printings bargain hunting
# matches eBay listings against — each wishlist author's living/dead
# status, for the buy-new rule, and the printings' cover groups
# (docs/BARGAIN_HUNTING.md). Scheduled daily
# (config/recurring.yml); items are only re-queried weekly (printings) or
# monthly (authors), so most runs touch a handful of new wishlist items.
class WishlistPrintingRefreshJob < ApplicationJob
  queue_as :default

  def perform
    printings = Isfdb::WishlistPrintingRefresh.run
    Rails.logger.info("wishlist printing refresh: #{printings}")
    authors = Isfdb::WishlistAuthorRefresh.run
    Rails.logger.info("wishlist author refresh: #{authors}")
    covers = WishlistCoverGrouping.run
    Rails.logger.info("wishlist cover grouping: #{covers}")
    "printings: #{printings}; authors: #{authors}; covers: #{covers}"
  end
end

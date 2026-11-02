# Nightly upkeep for the wishlist's bargain hunting (docs/BARGAIN_HUNTING.md,
# docs/CATALOG.md): each wanted book's author as living or dead, for the
# buy-new rule, and its printings' cover groups. The printings themselves
# are its Work's provider editions, fetched by KnownEditionsRefresh at 2:40
# (config/recurring.yml) — this runs after it. Authors are re-checked
# monthly and books regrouped only when their printings change, so most
# nights touch a handful of new wishlist books.
class WishlistRefreshJob < ApplicationJob
  queue_as :default

  def perform
    authors = Isfdb::ContributorLifeRefresh.run
    Rails.logger.info("contributor life refresh: #{authors}")
    covers = WishlistCoverGrouping.run
    Rails.logger.info("wishlist cover grouping: #{covers}")
    "authors: #{authors}; covers: #{covers}"
  end
end

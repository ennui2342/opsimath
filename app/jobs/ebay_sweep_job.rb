# Searches eBay for every hunted wishlist book, then identifies the
# printing of a batch of new listings (docs/BARGAIN_HUNTING.md). No
# notifications yet (build step 4).
class EbaySweepJob < ApplicationJob
  queue_as :default

  def perform
    sweep = Ebay::Sweep.run
    Rails.logger.info("eBay sweep: #{sweep}")
    identified = Ebay::PrintingIdentifier.run
    Rails.logger.info("eBay printing identification: #{identified}")
    "sweep: #{sweep}; identify: #{identified}"
  end
end

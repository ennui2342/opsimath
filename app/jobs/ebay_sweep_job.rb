# Searches eBay for every hunted wishlist book, identifies the printing
# of a batch of new listings, then posts the day's new finds to Discord
# (docs/BARGAIN_HUNTING.md).
class EbaySweepJob < ApplicationJob
  queue_as :default

  def perform
    sweep = Ebay::Sweep.run
    Rails.logger.info("eBay sweep: #{sweep}")
    identified = Ebay::PrintingIdentifier.run
    Rails.logger.info("eBay printing identification: #{identified}")
    announced = FindsDigest.run
    "sweep: #{sweep}; identify: #{identified}; new finds announced: #{announced}"
  end
end

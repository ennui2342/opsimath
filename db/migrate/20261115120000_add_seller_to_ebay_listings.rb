# The listing's seller (eBay Browse: seller.username, feedbackScore,
# feedbackPercentage) — Mark combines purchases from one seller to save
# postage (2026-11-15).
class AddSellerToEbayListings < ActiveRecord::Migration[8.1]
  def change
    add_column :ebay_listings, :seller, :string
    add_column :ebay_listings, :seller_feedback_score, :integer
    add_column :ebay_listings, :seller_feedback_percentage, :string
  end
end

# One eBay listing seen for a hunted wishlist book (docs/BARGAIN_HUNTING.md).
# Written by Ebay::Sweep, identified by Ebay::PrintingIdentifier. Kept
# after the listing ends: these rows are the per-printing price history.
class EbayListing < ApplicationRecord
  belongs_to :wishlist_item

  scope :live, -> { where(ended_at: nil) }
  scope :unidentified, -> { where(identified_by: nil) }

  def auction? = buying_options.include?("AUCTION")

  # What it would cost now, delivered: the current bid for an auction
  # (the Buy It Now price if it has one), postage included when known.
  def total
    base = auction? && current_bid ? current_bid : price
    base && base + shipping.to_i
  end

  def printings
    wishlist_item.wishlist_printings.select { |p| matched_pub_ids.include?(p.isfdb_pub_id) }
  end
end

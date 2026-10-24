# Printings of a wishlist book that share a cover — the unit Mark picks
# in the cover picker and the unit prices are compared in
# (docs/BARGAIN_HUNTING.md). Computed by WishlistCoverGrouping.
class AddCoverGroupsToWishlistPrintings < ActiveRecord::Migration[8.1]
  def change
    add_column :wishlist_printings, :cover_group, :bigint # the group's representative isfdb_pub_id
    add_column :wishlist_items, :cover_groups_digest, :string # of the printings grouped; regroup when it changes
  end
end

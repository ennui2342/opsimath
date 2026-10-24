# Bargain hunting, build step 2 (docs/BARGAIN_HUNTING.md): every eBay
# listing seen for a hunted wishlist book, which printing(s) it was
# identified as, and when it was seen. Rows are kept after a listing
# ends — they're the price history.
class CreateEbayListings < ActiveRecord::Migration[8.1]
  def change
    create_table :ebay_listings do |t|
      t.references :wishlist_item, null: false, foreign_key: true, index: false # covered by the unique index below
      t.string :ebay_item_id, null: false
      t.string :title, null: false
      t.string :url
      t.string :image_url
      t.integer :price # pence, GBP (eBay converts); the Buy It Now price
      t.integer :current_bid # pence; auctions only
      t.integer :shipping # pence; null = unknown / collection only
      t.string :shipping_type # FIXED / CALCULATED
      t.string :original_currency # when eBay converted the price to GBP
      t.string :condition
      t.string :buying_options, array: true, null: false, default: []
      t.datetime :auction_ends_at
      t.integer :bid_count
      t.string :seller_country
      t.string :found_by, null: false # keyword / gtin
      t.bigint :matched_pub_ids, array: true, null: false, default: [] # isfdb_pub_ids: one printing, or a shared-cover group
      t.string :identified_by # cover / text / unknown; null = not tried yet
      t.jsonb :cover_scores, null: false, default: {} # isfdb_pub_id => { ratio, inliers }
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_at
      t.datetime :notified_at
      t.string :status, null: false, default: "new" # new / dismissed / bought
      t.timestamps
    end
    add_index :ebay_listings, [ :wishlist_item_id, :ebay_item_id ], unique: true
  end
end

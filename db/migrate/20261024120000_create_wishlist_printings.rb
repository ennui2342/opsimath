# Bargain hunting, build step 1 (docs/BARGAIN_HUNTING.md): the ISFDB
# printings of each wishlist book, the author's living/dead status (for
# the buy-new rule), the collecting profile that decides what's wanted,
# and the per-item knobs (target price, explicit printing choice,
# buy-new override).
class CreateWishlistPrintings < ActiveRecord::Migration[8.1]
  def change
    create_table :wishlist_printings do |t|
      t.references :wishlist_item, null: false, foreign_key: true, index: false # covered by the unique index below
      t.bigint :isfdb_pub_id, null: false
      t.string :isbn13
      t.string :isbn10
      t.string :publisher
      t.string :binding, null: false
      t.string :publish_date # EDTF, as Edition.publish_date
      t.string :cover_artist
      t.string :cover_url
      t.timestamps
    end
    add_index :wishlist_printings, [ :wishlist_item_id, :isfdb_pub_id ], unique: true

    change_table :wishlist_items, bulk: true do |t|
      t.integer :target_price # pence
      t.bigint :printing_override_ids, array: true # isfdb_pub_ids; null = use the collecting profile
      t.datetime :printings_refreshed_at
      t.boolean :buy_new_override # null = the profile decides; true = always buy new; false = always hunt
      t.bigint :author_isfdb_id
      t.string :author_died_date # EDTF; null with an author_isfdb_id = living
      t.datetime :author_checked_at
    end

    create_table :collecting_profiles do |t|
      t.integer :recent_years, null: false, default: 5
      t.integer :favourite_artist_min_owned, null: false, default: 5
      t.string :favourite_artists_always, array: true, null: false, default: []
      t.string :favourite_artists_never, array: true, null: false, default: []
      t.timestamps
    end
  end
end

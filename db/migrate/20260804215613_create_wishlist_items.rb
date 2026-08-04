class CreateWishlistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wishlist_items do |t|
      t.string :title, null: false
      t.string :author_name
      t.string :cover_url
      t.references :work, foreign_key: true
      t.references :series, foreign_key: true
      t.integer :priority
      t.text :notes
      t.jsonb :external_ids, null: false, default: {}

      t.timestamps
    end
  end
end

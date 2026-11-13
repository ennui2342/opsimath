# Reading lists (docs/LISTS.md): award categories from ISFDB and fixed
# published lists (Pringle 100, Broderick 101), and collecting one.
class CreateBookLists < ActiveRecord::Migration[8.1]
  def change
    create_table :book_lists do |t|
      t.string :key, null: false # "pringle_100", or "isfdb_award_category:123"
      t.string :name, null: false
      t.string :short_name, null: false # for book-page badges: "Clarke Award", "Pringle 100"
      t.string :kind, null: false # award | curated
      t.integer :isfdb_award_category_id
      t.string :source
      t.datetime :synced_at
      t.timestamps
      t.index :key, unique: true
    end

    create_table :book_list_entries do |t|
      t.references :book_list, null: false, foreign_key: true
      t.integer :year
      t.integer :position
      t.string :status, null: false # winner | shortlisted | listed
      t.string :title, null: false
      t.string :author
      t.integer :isfdb_title_id
      t.timestamps
      t.index :isfdb_title_id
    end

    create_table :book_list_wants do |t|
      t.references :book_list, null: false, foreign_key: true, index: { unique: true }
      t.string :scope, null: false, default: "winners" # winners | shortlist
      t.integer :from_year
      t.integer :excluded_title_ids, array: true, null: false, default: []
      t.datetime :synced_at
      t.timestamps
    end

    add_reference :wants, :book_list_want, foreign_key: true
  end
end

# System-of-record step 2 (docs/CATALOG.md, "Architecture review"): the
# editions providers know for each work, in one table — replacing the
# ISBN-only WorkSiblingIsbns cache, and to serve the edition picker and
# (from step 4) bargain hunting — and identifiers for works, as editions
# already have.
class CreateProviderEditionsAndWorkIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_editions do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }, index: false # covered below
      t.string :provider, null: false       # isfdb / openlibrary
      t.string :provider_id, null: false    # ISFDB pub id, Open Library edition key
      t.string :isbn13
      t.string :isbn10
      t.string :title
      t.string :publisher
      t.string :binding                     # provider's own code (ISFDB pb / tp / hc / ebook / …)
      t.string :publish_date                # EDTF, as Edition.publish_date
      t.string :language
      t.integer :page_count
      t.string :cover_url
      t.string :cover_artist                # "First, Second", as Edition.cover_artist
      t.string :cover_group                 # provider_id of the group's representative edition
      t.timestamps
    end
    add_index :provider_editions, [ :work_id, :provider, :provider_id ], unique: true
    add_index :provider_editions, :isbn13

    create_table :work_identifiers do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }, index: false # covered below
      t.string :id_type, null: false        # isfdb_title / openlibrary_work
      t.string :value, null: false
      t.string :source                      # how it was learnt, e.g. isbn_lookup
      t.timestamps
    end
    add_index :work_identifiers, [ :work_id, :id_type, :value ], unique: true
    # Not unique per (id_type, value): an omnibus edition's ISBN resolves to
    # a novel inside it in ISFDB, so two works can legitimately share one.
    add_index :work_identifiers, [ :id_type, :value ]

    change_table :works, bulk: true do |t|
      t.datetime :known_editions_refreshed_at
      t.string :known_editions_queried_isbns, array: true, null: false, default: []
    end
  end
end

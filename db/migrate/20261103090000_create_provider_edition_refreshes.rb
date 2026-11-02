# Catalogue step 3 (docs/CATALOG.md): with a second provider, "when were
# this work's known editions last fetched, and from which ISBNs" is per
# provider — moved off `works` (one provider's worth of columns, added in
# step 2) into its own table. ISFDB's existing values carry over, so the
# next refresh doesn't re-fetch every work.
class CreateProviderEditionRefreshes < ActiveRecord::Migration[8.1]
  def up
    create_table :provider_edition_refreshes do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }, index: false # covered below
      t.string :provider, null: false
      t.datetime :refreshed_at, null: false
      t.string :queried_isbns, array: true, null: false, default: []
    end
    add_index :provider_edition_refreshes, [ :work_id, :provider ], unique: true

    execute <<~SQL
      INSERT INTO provider_edition_refreshes (work_id, provider, refreshed_at, queried_isbns)
      SELECT id, 'isfdb', known_editions_refreshed_at, known_editions_queried_isbns
        FROM works WHERE known_editions_refreshed_at IS NOT NULL
    SQL

    remove_column :works, :known_editions_refreshed_at
    remove_column :works, :known_editions_queried_isbns
  end

  def down
    add_column :works, :known_editions_refreshed_at, :datetime
    add_column :works, :known_editions_queried_isbns, :string, array: true, null: false, default: []
    execute <<~SQL
      UPDATE works SET known_editions_refreshed_at = r.refreshed_at, known_editions_queried_isbns = r.queried_isbns
        FROM provider_edition_refreshes r WHERE r.work_id = works.id AND r.provider = 'isfdb'
    SQL
    drop_table :provider_edition_refreshes
  end
end

# A readable record of what changed in the catalogue, posted to Discord's
# #catalogue (CatalogueReport): Mark's edits batched every 15 minutes, the
# overnight jobs' changes as a morning digest.
class CreateCatalogueEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :catalogue_events do |t|
      t.string :origin, null: false   # "web" for Mark's edits, else the job ("known_editions", "sweep", …)
      t.string :kind, null: false     # "added", "printing_changed", "new_printings", …
      t.references :work, foreign_key: { on_delete: :nullify }
      t.text :summary, null: false    # one line, as posted
      t.jsonb :details, null: false, default: {}
      t.datetime :reported_at
      t.datetime :created_at, null: false
    end
    add_index :catalogue_events, [ :origin, :reported_at ]
  end
end

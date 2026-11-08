# Wanting a whole publisher's line (ISFDB publication series): one record
# per line Mark collects; each night it wants every number he doesn't have
# (LineWants::Sync). A want it created remembers that (wants.line_want_id),
# so stopping removes only those.
class CreateLineWants < ActiveRecord::Migration[8.1]
  def change
    create_table :line_wants do |t|
      t.integer :pub_series_id, null: false, index: { unique: true }
      t.string :name
      t.integer :excluded_pub_ids, array: true, null: false, default: []
      t.datetime :synced_at
      t.timestamps
    end
    add_reference :wants, :line_want, foreign_key: { on_delete: :nullify }
  end
end

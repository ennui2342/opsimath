# Collecting a whole story series (The Snow Queen Cycle): one record per
# series; each night every book in it Mark doesn't have becomes a want
# (SeriesWants::Sync) — the book, not a printing. A want it created
# remembers that, so stopping removes only those.
class CreateSeriesWants < ActiveRecord::Migration[8.1]
  def change
    create_table :series_wants do |t|
      t.references :series, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :excluded_title_ids, array: true, null: false, default: [] # ISFDB title ids: "not this one"
      t.datetime :synced_at
      t.timestamps
    end
    add_reference :wants, :series_want, foreign_key: { on_delete: :nullify }
  end
end

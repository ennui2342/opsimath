# One row, updated in place each rebuild — the current offline snapshot
# for the shop-lookup PWA (docs/MOBILE.md). The SQLite file itself is an
# Active Storage attachment; `version` is the monotonic number the client
# polls to decide whether to re-download.
class CreateMobileSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_snapshots do |t|
      t.integer :version, null: false, default: 0
      t.datetime :generated_at
      t.bigint :byte_size
      t.integer :entry_count
      t.timestamps
    end
  end
end

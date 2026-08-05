class CreateGoodreadsSyncStates < ActiveRecord::Migration[8.1]
  # Per docs/INTEGRATIONS.md's Phase 2 design: one row per
  # (goodreads_book_id, shelf), holding the last-synced snapshot needed to
  # detect a genuine change on the next poll. Comparison is always against
  # this latest snapshot, never a permanent "have we ever seen this" set —
  # see the doc for why (a reverted value must not look "already handled").
  def change
    create_table :goodreads_sync_states do |t|
      t.string :goodreads_book_id, null: false
      t.string :shelf, null: false
      t.jsonb :last_synced_payload, null: false, default: {}

      t.timestamps
    end
    add_index :goodreads_sync_states, [ :goodreads_book_id, :shelf ], unique: true
  end
end

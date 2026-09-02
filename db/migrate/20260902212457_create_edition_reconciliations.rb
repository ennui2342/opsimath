class CreateEditionReconciliations < ActiveRecord::Migration[8.1]
  def up
    create_table :edition_reconciliations do |t|
      t.bigint :work_id, null: false
      t.string :run_id
      t.jsonb :payload, default: {}, null: false
      t.string :resolution
      t.bigint :resolved_edition_id
      t.string :status, default: "pending", null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :edition_reconciliations, :status
    add_index :edition_reconciliations, :work_id

    # Every existing Reading is an owned-copy read — the Goodreads sync
    # only ever catalogued books it also created an owned Copy for. Set
    # the column now so `source` is meaningful everywhere, not just on
    # rows written after this.
    Reading.where(source: nil).update_all(source: "owned_copy")
  end

  def down
    drop_table :edition_reconciliations
  end
end

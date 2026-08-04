class CreatePendingDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_decisions do |t|
      t.string :kind, null: false
      t.string :run_id
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :resolved_at

      t.timestamps
    end
    add_index :pending_decisions, :status
  end
end

class CreateJobItems < ActiveRecord::Migration[8.1]
  def change
    create_table :job_items do |t|
      t.string :run_id, null: false
      t.references :entity, polymorphic: true, null: false
      t.string :status, null: false
      t.text :message

      t.timestamps
    end
    add_index :job_items, :run_id
  end
end

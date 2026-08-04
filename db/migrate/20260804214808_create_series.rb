class CreateSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :series do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "ongoing"
      t.integer :total_count
      t.jsonb :field_sources, null: false, default: {}

      t.timestamps
    end
  end
end

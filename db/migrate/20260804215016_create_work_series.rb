class CreateWorkSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :work_series do |t|
      t.references :work, null: false, foreign_key: true
      t.references :series, null: false, foreign_key: true
      t.references :arc, foreign_key: { to_table: :series_arcs }
      t.decimal :position

      t.timestamps
    end
  end
end

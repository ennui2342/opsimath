class CreateSeriesArcs < ActiveRecord::Migration[8.1]
  def change
    create_table :series_arcs do |t|
      t.references :series, null: false, foreign_key: true
      t.string :name
      t.decimal :position

      t.timestamps
    end
  end
end

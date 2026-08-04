class CreateCopies < ActiveRecord::Migration[8.1]
  def change
    create_table :copies do |t|
      t.references :edition, null: false, foreign_key: true
      t.string :condition
      t.date :acquired_date
      t.string :acquired_source
      t.decimal :acquired_price, precision: 10, scale: 2
      t.text :inscription
      t.references :storage_location, foreign_key: true
      t.string :disposition, null: false, default: "owned"
      t.text :notes

      t.timestamps
    end
  end
end

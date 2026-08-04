class CreateReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :readings do |t|
      t.references :work, null: false, foreign_key: true
      t.references :edition, null: false, foreign_key: true
      t.references :copy, foreign_key: true
      t.string :status, null: false
      t.date :date_started
      t.date :date_finished
      t.string :dnf_reason
      t.decimal :rating, precision: 3, scale: 1
      t.text :private_notes
      t.string :source

      t.timestamps
    end
  end
end

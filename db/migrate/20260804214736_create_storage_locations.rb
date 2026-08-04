class CreateStorageLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :storage_locations do |t|
      t.string :name, null: false
      t.references :parent_location, foreign_key: { to_table: :storage_locations }

      t.timestamps
    end
  end
end

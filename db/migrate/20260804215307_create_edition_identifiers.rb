class CreateEditionIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :edition_identifiers do |t|
      t.references :edition, null: false, foreign_key: true
      t.string :id_type, null: false
      t.string :value, null: false
      t.string :notes

      t.timestamps
    end
    add_index :edition_identifiers, %i[id_type value]
  end
end

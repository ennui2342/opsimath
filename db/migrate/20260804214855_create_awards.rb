class CreateAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :awards do |t|
      t.string :name, null: false
      t.string :wikidata_id

      t.timestamps
    end
  end
end

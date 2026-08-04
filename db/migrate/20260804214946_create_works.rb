class CreateWorks < ActiveRecord::Migration[8.1]
  def change
    create_table :works do |t|
      t.string :title, null: false
      t.string :subtitle
      t.string :work_type, null: false
      t.integer :original_publication_year
      t.string :original_language
      t.text :description
      t.text :notes
      t.jsonb :field_sources, null: false, default: {}

      t.timestamps
    end
    add_index :works, :title
  end
end

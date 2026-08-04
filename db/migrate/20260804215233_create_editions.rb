class CreateEditions < ActiveRecord::Migration[8.1]
  def change
    create_table :editions do |t|
      t.string :format, null: false
      t.string :format_detail
      t.string :publisher
      t.string :imprint
      t.date :publish_date
      t.string :publish_date_precision
      t.string :printing
      t.string :edition_name
      t.references :variant_of_edition, foreign_key: { to_table: :editions }
      t.integer :page_count
      t.integer :duration_seconds
      t.string :language
      t.text :description
      t.jsonb :field_sources, null: false, default: {}

      t.timestamps
    end
  end
end

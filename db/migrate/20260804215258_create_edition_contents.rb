class CreateEditionContents < ActiveRecord::Migration[8.1]
  def change
    create_table :edition_contents do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :work, null: false, foreign_key: true
      t.integer :display_order
      t.string :billing
      t.integer :page_start

      t.timestamps
    end
  end
end

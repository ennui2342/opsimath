class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :work, null: false, foreign_key: true
      t.references :reading, foreign_key: true
      t.text :text
      t.decimal :rating, precision: 3, scale: 1
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.jsonb :channels, null: false, default: []

      t.timestamps
    end
  end
end

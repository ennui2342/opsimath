class CreateWorkGenres < ActiveRecord::Migration[8.1]
  def change
    create_table :work_genres do |t|
      t.references :work, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true

      t.timestamps
    end
    add_index :work_genres, %i[work_id genre_id], unique: true
  end
end

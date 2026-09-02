class CreateMobileThumbs < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_thumbs, id: false do |t|
      t.string :blob_key, null: false
      t.binary :data, null: false
      t.integer :byte_size, null: false
      t.datetime :created_at, null: false
    end
    add_index :mobile_thumbs, :blob_key, unique: true
  end
end

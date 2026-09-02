class CreateWorkSiblingIsbns < ActiveRecord::Migration[8.1]
  def change
    create_table :work_sibling_isbns, id: false do |t|
      t.bigint :work_id, null: false
      t.string :isbn13s, array: true, null: false, default: []
      t.string :queried_isbns, array: true, null: false, default: []
      t.datetime :refreshed_at, null: false
    end
    add_index :work_sibling_isbns, :work_id, unique: true
  end
end

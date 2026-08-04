class CreateWorkTags < ActiveRecord::Migration[8.1]
  def change
    create_table :work_tags do |t|
      t.references :work, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
    add_index :work_tags, %i[work_id tag_id], unique: true
  end
end

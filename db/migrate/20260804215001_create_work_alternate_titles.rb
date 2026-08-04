class CreateWorkAlternateTitles < ActiveRecord::Migration[8.1]
  def change
    create_table :work_alternate_titles do |t|
      t.references :work, null: false, foreign_key: true
      t.string :title, null: false
      t.string :note

      t.timestamps
    end
  end
end

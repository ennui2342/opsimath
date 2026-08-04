class CreateWorkAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :work_awards do |t|
      t.references :work, null: false, foreign_key: true
      t.references :award, null: false, foreign_key: true
      t.integer :year
      t.string :status, null: false

      t.timestamps
    end
  end
end

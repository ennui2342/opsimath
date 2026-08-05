class CreateSubjects < ActiveRecord::Migration[8.1]
  def change
    create_table :subjects do |t|
      t.string :name, null: false
      t.string :ddc_code

      t.timestamps
    end
    add_index :subjects, :name, unique: true
  end
end

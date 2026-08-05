class CreateWorkSubjects < ActiveRecord::Migration[8.1]
  def change
    create_table :work_subjects do |t|
      t.references :work, null: false, foreign_key: true
      t.references :subject, null: false, foreign_key: true

      t.timestamps
    end
    add_index :work_subjects, %i[work_id subject_id], unique: true
  end
end

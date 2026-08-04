class CreateWorkContributors < ActiveRecord::Migration[8.1]
  def change
    create_table :work_contributors do |t|
      t.references :work, null: false, foreign_key: true
      t.references :contributor, null: false, foreign_key: true
      t.string :role, null: false
      t.integer :display_order
      t.string :credited_as

      t.timestamps
    end
    add_index :work_contributors, %i[work_id contributor_id role], unique: true, name: "index_work_contributors_on_work_contributor_role"
  end
end

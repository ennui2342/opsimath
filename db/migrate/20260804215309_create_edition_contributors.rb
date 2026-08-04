class CreateEditionContributors < ActiveRecord::Migration[8.1]
  def change
    create_table :edition_contributors do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :contributor, null: false, foreign_key: true
      t.string :role, null: false
      t.integer :display_order
      t.string :credited_as

      t.timestamps
    end
    add_index :edition_contributors, %i[edition_id contributor_id role], unique: true, name: "index_edition_contributors_on_edition_contributor_role"
  end
end

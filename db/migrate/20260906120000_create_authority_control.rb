class CreateAuthorityControl < ActiveRecord::Migration[8.1]
  def change
    create_table :authority_terms do |t|
      t.string :vocabulary, null: false
      t.string :preferred_label, null: false
      t.timestamps
    end
    add_index :authority_terms, %i[vocabulary preferred_label], unique: true

    create_table :authority_variants do |t|
      t.references :authority_term, null: false, foreign_key: true
      # denormalised from the term so the "one meaning per string per
      # vocabulary" rule can be a real DB unique index, not an app check
      t.string :vocabulary, null: false
      t.string :label, null: false
      t.string :normalized_label, null: false
      t.timestamps
    end
    add_index :authority_variants, %i[vocabulary normalized_label], unique: true
  end
end

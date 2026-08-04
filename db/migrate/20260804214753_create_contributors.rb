class CreateContributors < ActiveRecord::Migration[8.1]
  def change
    create_table :contributors do |t|
      t.string :name, null: false
      t.string :sort_name
      t.text :bio
      t.jsonb :external_ids, null: false, default: {}
      t.jsonb :field_sources, null: false, default: {}

      t.timestamps
    end
  end
end

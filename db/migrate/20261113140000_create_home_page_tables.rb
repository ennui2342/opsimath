# The home page (docs/HOME.md): a yearly reading goal, and the
# recommendations Mark has put off ("Not now", until a date) or ruled out
# ("Not for me", for good), plus which were shown — so the recommender's
# weights can later be tuned from what he actually went on to read.
class CreateHomePageTables < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_goals do |t|
      t.integer :year, null: false, index: { unique: true }
      t.integer :target, null: false
      t.timestamps
    end

    create_table :recommendation_dismissals do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.datetime :until # nil: for good
      t.timestamps
    end

    create_table :recommendation_shows do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }
      t.string :reason, null: false
      t.date :shown_on, null: false
      t.timestamps
      t.index %i[work_id shown_on], unique: true
    end

    reversible { |dir| dir.up { execute "INSERT INTO reading_goals (year, target, created_at, updated_at) VALUES (2026, 78, now(), now())" } }
  end
end

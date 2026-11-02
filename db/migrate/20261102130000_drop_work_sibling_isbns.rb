# Replaced by provider_editions (docs/CATALOG.md, "Architecture review");
# verified 2026-11-02 on a production copy: the shop app's sibling ISBNs
# came out identical for 2,031 of 2,034 works, the other three each
# gaining one printing ISFDB added since the old cache's last refresh.
class DropWorkSiblingIsbns < ActiveRecord::Migration[8.1]
  def up
    drop_table :work_sibling_isbns
  end

  def down
    create_table :work_sibling_isbns, id: false do |t|
      t.bigint :work_id, null: false
      t.string :isbn13s, array: true, null: false, default: []
      t.string :queried_isbns, array: true, null: false, default: []
      t.datetime :refreshed_at, null: false
    end
    add_index :work_sibling_isbns, :work_id, unique: true
  end
end

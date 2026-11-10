# A book's ISFDB main title and its variants (isfdb-adapter /titles/:id),
# kept for TitleCleanup: the main title is the book's title (Mark,
# 2026-11-10); a current title that's one of the variants is the same book
# known by another title, not a wrong link.
class AddIsfdbTitlesToWorks < ActiveRecord::Migration[8.1]
  def change
    add_column :works, :isfdb_main_title, :string
    add_column :works, :isfdb_variant_titles, :string, array: true, null: false, default: []
    add_column :works, :isfdb_titles_checked_at, :datetime
  end
end

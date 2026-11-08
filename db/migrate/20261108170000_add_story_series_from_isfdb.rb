# A book's story series from ISFDB (The Snow Queen Cycle, 448), for
# filing books in their series — until now series came only from the
# Goodreads import, and Add a book set none.
class AddStorySeriesFromIsfdb < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :isfdb_series_id, :integer
    add_index :series, :isfdb_series_id, unique: true

    # The printing's title's series, as ISFDB gives it on every printing.
    add_column :provider_editions, :series_id, :integer
    add_column :provider_editions, :series_name, :string
    add_column :provider_editions, :series_num, :decimal
  end
end

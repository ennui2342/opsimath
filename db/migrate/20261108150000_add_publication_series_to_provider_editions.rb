# A printing's publisher's line — ISFDB's publication series (The Women's
# Press Science Fiction; the SF Master Series, 579) — and its number in it.
class AddPublicationSeriesToProviderEditions < ActiveRecord::Migration[8.1]
  def change
    add_column :provider_editions, :pub_series_id, :integer
    add_column :provider_editions, :pub_series_name, :string
    add_column :provider_editions, :pub_series_num, :string
    add_index :provider_editions, :pub_series_id
  end
end

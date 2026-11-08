# Each printing's credited authors with their ISFDB ids — tying the
# catalogue's authors to ISFDB through their books (AuthorLinks), not by
# name.
class AddAuthorsToProviderEditions < ActiveRecord::Migration[8.1]
  def change
    add_column :provider_editions, :author_names, :string, array: true, null: false, default: []
    add_column :provider_editions, :author_ids, :integer, array: true, null: false, default: []
  end
end

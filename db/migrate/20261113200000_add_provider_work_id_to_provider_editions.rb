# The provider's title (ISFDB) or work (Open Library) a printing is a
# printing of — its own, not a book it contains. "A book's own printings"
# becomes exact, and a book's ISFDB link can be derived from its editions'
# printings (docs/CATALOG.md, "ISFDB links from editions").
class AddProviderWorkIdToProviderEditions < ActiveRecord::Migration[8.1]
  def change
    add_column :provider_editions, :provider_work_id, :string
  end
end

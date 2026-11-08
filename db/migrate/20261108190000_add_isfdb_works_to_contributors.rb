# An author's ISFDB bibliography, kept for their page (AuthorBibliography):
# fetched in the background — it takes isfdb-adapter up to ~30s to build
# for a prolific author — and refreshed weekly when the page is visited.
class AddIsfdbWorksToContributors < ActiveRecord::Migration[8.1]
  def change
    add_column :contributors, :isfdb_works, :jsonb
    add_column :contributors, :isfdb_works_fetched_at, :datetime
  end
end

# The author-status half of the buy-new rule as a switch (Mark, 2026-11-07:
# he expects to turn it off and go by recency alone).
class AddBuyNewForLivingAuthorsToCollectingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :collecting_profiles, :buy_new_for_living_authors, :boolean, null: false, default: true
  end
end

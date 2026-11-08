# The "book club editions are never wanted" rule as a setting, not a
# special case (Mark, 2026-11-08) — like the living-author rule.
class AddExcludeBookClubsToCollectingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :collecting_profiles, :exclude_book_clubs, :boolean, null: false, default: true
  end
end

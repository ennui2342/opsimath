# The UPC add-on lookup learnt only digits-5-9 prefixes until 2026-11-13;
# DAW's add-on is the title part (0-88677-299-0 → 00299), so its scans left
# wrong candidates (Avon's, Pinnacle's). Unresolved rows start afresh under
# the corrected rule; resolved ones (Bantam, Ace, Pocket, Tor...) were
# right and stay.
class ClearUnresolvedUpcPrefixes < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM upc_prefixes WHERE prefix IS NULL"
  end

  def down; end
end

class AddIsfdbNamesToContributors < ActiveRecord::Migration[8.1]
  # ISFDB's pseudonym links for the author (isfdb-adapter /authors
  # pseudonyms, pseudonym_of): { "pseudonyms" => [{id, name}], "pseudonym_of" => [{id, name}] }.
  def change
    add_column :contributors, :isfdb_names, :jsonb
  end
end

# A UPC publisher can have several ISBN prefixes (Tor's UPC 037145 is
# both 0812 and 0765; S&S's 076714 is 0671 and 0743), so `prefix` becomes a
# list. Seeded from LibraryThing's UPC vendor → ISBN vendor table
# (wiki.librarything.com/index.php/ISBN, "UPC to ISBN conversion"),
# keyed by UPC digits 2–6.
class AddKnownPrefixesToUpcPrefixes < ActiveRecord::Migration[8.1]
  LIBRARYTHING = [
    %w[018926 0445], %w[027778 0449], %w[037145 0812], %w[037145 0765], %w[042799 0785], %w[043144 0688], %w[044903 0312],
    %w[045863 0517], %w[046594 0694], %w[047132 0152], %w[050694 0345], %w[051487 0816], %w[051488 0140], %w[060771 0002],
    %w[065373 0373], %w[070992 0523], %w[070993 0446], %w[070999 0345], %w[071001 0380], %w[071009 0440], %w[071125 0886],
    %w[071136 0451], %w[071149 0451], %w[071152 0515], %w[071162 0451], %w[071268 0821], %w[071831 0425], %w[071842 0843],
    %w[072742 0441], %w[076714 0671], %w[076714 0743], %w[076783 0553], %w[076814 0449], %w[077434 0743], %w[078021 0872],
    %w[079808 0394], %w[090129 0679], %w[099455 0061], %w[099769 0451], %w[645573 1595]
  ].freeze

  def up
    add_column :upc_prefixes, :known_prefixes, :string, array: true, null: false, default: []
    execute "UPDATE upc_prefixes SET known_prefixes = ARRAY[prefix] WHERE prefix IS NOT NULL"
    LIBRARYTHING.group_by { |vendor, _| vendor[1, 5] }.each do |manufacturer, rows|
      known = rows.map(&:last)
      execute <<~SQL
        INSERT INTO upc_prefixes (manufacturer, candidates, known_prefixes, created_at, updated_at)
        VALUES (#{quote(manufacturer)}, '{}', ARRAY[#{known.map { |p| quote(p) }.join(',')}]::varchar[], now(), now())
        ON CONFLICT (manufacturer) DO UPDATE
          SET known_prefixes = (SELECT ARRAY(SELECT DISTINCT unnest(upc_prefixes.known_prefixes || EXCLUDED.known_prefixes)))
      SQL
    end
    remove_column :upc_prefixes, :prefix
  end

  def down
    add_column :upc_prefixes, :prefix, :string
    execute "UPDATE upc_prefixes SET prefix = known_prefixes[1]"
    remove_column :upc_prefixes, :known_prefixes
  end
end

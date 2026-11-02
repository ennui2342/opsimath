# Catalogue step 4 (docs/CATALOG.md, "Architecture review"): a wanted
# book becomes a Work with a Want, instead of a self-contained
# WishlistItem. The want sits on the Work, so no edition is committed to
# before one is owned.
#
# Converts every wishlist item:
# - its Work: an existing one when the item's ISBN is one of that work's
#   own or provider-known ISBNs *and* the short titles match (an ISBN
#   alone isn't enough — omnibus printings share ISBNs with the novels in
#   them: The Blue World / seven Vance works); otherwise a new one;
# - its author: an existing Contributor of that name, or a new one, now
#   carrying the life dates bargain hunting's buy-new rule needs;
# - a Want with its priority, notes, target price, cover choices, buy-new
#   override, the ISBNs it was wanted under, and its cover image (the
#   attachment moves; nothing is re-downloaded);
# - its ISFDB printings into provider_editions, cover groups included;
#   its eBay listings re-pointed at the work.
#
# wishlist_items and wishlist_printings are left in place, untouched,
# until the new structure is confirmed in production; a later migration
# drops them. Not reversible in code — the old tables are intact, and a
# full rollback is the pre-deploy database dump.
class WishlistJoinsTheCatalogue < ActiveRecord::Migration[8.1]
  class Item < ActiveRecord::Base
    self.table_name = "wishlist_items"
  end

  def up
    create_table :wants do |t|
      t.references :work, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :priority
      t.text :notes
      t.integer :target_price                               # pence
      t.bigint :printing_override_ids, array: true          # isfdb pub ids; null = the collecting profile decides
      t.boolean :buy_new_override                           # null = the profile decides
      t.string :seed_isbns, array: true, null: false, default: [] # the ISBN(s) it was wanted under
      t.string :cover_url
      t.jsonb :external_ids, null: false, default: {}       # e.g. goodreads (legacy dedupe)
      t.string :cover_groups_digest
      t.bigint :legacy_wishlist_item_id, index: { unique: true }
      t.timestamps
    end

    change_table :contributors, bulk: true do |t|
      t.string :died_date            # EDTF; null with an ISFDB id = living
      t.datetime :life_checked_at
    end

    add_reference :ebay_listings, :work, foreign_key: { on_delete: :cascade }, index: false
    remove_foreign_key :ebay_listings, :wishlist_items
    change_column_null :ebay_listings, :wishlist_item_id, true

    convert

    change_column_null :ebay_listings, :work_id, false
    add_index :ebay_listings, [ :work_id, :ebay_item_id ], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "restore the pre-deploy dump; wishlist_items/wishlist_printings are intact"
  end

  private

  def convert
    now = Time.current
    isbn_works = isbn_index
    titles = select_rows("SELECT id, title FROM works").to_h

    Item.order(:id).find_each do |item|
      ext = item.external_ids || {}
      seeds = [ ext["isbn13"].presence, ext["isbn10"].presence && Isbn.to_13(ext["isbn10"]) ].compact.uniq
      printing_isbns = select_values(sanitize("SELECT COALESCE(isbn13, isbn10) FROM wishlist_printings WHERE wishlist_item_id = ?", item.id))
                       .compact.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact
      candidates = (seeds + printing_isbns).flat_map { |i| isbn_works[i] || [] }.uniq
      same_title = candidates.select { |w| short(titles[w]) == short(item.title) }

      work_id = same_title.one? ? same_title.first : insert_work(item, now)
      next if select_value(sanitize("SELECT 1 FROM wants WHERE work_id = ?", work_id)) # a second item for the same book: the first wins

      link_author(work_id, item, now)
      link_series(work_id, item.series_id, now) if item.series_id
      want_id = insert_want(work_id, item, seeds, now)

      execute sanitize("UPDATE active_storage_attachments SET record_type = 'Want', record_id = ? " \
                       "WHERE record_type = 'WishlistItem' AND record_id = ? AND name = 'cover_image'", want_id, item.id)
      copy_printings(work_id, item.id, now)
      record_refresh(work_id, item, seeds)
      execute sanitize("UPDATE ebay_listings SET work_id = ? WHERE wishlist_item_id = ?", work_id, item.id)
    end

    # Any listing left without a work belonged to a duplicate item; the
    # first item's listings stand for that book.
    execute "DELETE FROM ebay_listings WHERE work_id IS NULL"
  end

  # {ISBN-13 => [work_id, ...]} over the catalogue's own editions and
  # every provider-known edition.
  def isbn_index
    index = Hash.new { |h, k| h[k] = [] }
    select_rows(<<~SQL).each { |work_id, type, value| (i = type == "isbn10" ? Isbn.to_13(value) : value) && index[i] |= [ work_id ] }
      SELECT ec.work_id, ei.id_type, ei.value FROM edition_identifiers ei
        JOIN edition_contents ec ON ec.edition_id = ei.edition_id
       WHERE ei.id_type IN ('isbn13', 'isbn10')
      UNION
      SELECT work_id, 'isbn13', isbn13 FROM provider_editions WHERE isbn13 IS NOT NULL
      UNION
      SELECT work_id, 'isbn10', isbn10 FROM provider_editions WHERE isbn10 IS NOT NULL
    SQL
    index
  end

  def insert_work(item, now)
    select_value(sanitize("INSERT INTO works (title, literary_form, field_sources, created_at, updated_at) VALUES (?, 'novel', ?, ?, ?) RETURNING id",
                          item.title, { "title" => "goodreads" }.to_json, now, now))
  end

  # A work that already has an author (a want joining an existing work)
  # keeps it — and gains the item's author check, if it had none.
  def link_author(work_id, item, now)
    return if item.author_name.blank?

    existing = select_value(sanitize("SELECT contributor_id FROM work_contributors WHERE work_id = ? AND role = 'author' " \
                                     "ORDER BY display_order NULLS LAST, id LIMIT 1", work_id))
    return copy_life_dates(existing, item) if existing

    contributor_id = select_value(sanitize("SELECT id FROM contributors WHERE lower(name) = lower(?) ORDER BY id LIMIT 1", item.author_name)) ||
                     select_value(sanitize("INSERT INTO contributors (name, external_ids, field_sources, created_at, updated_at) VALUES (?, '{}', '{}', ?, ?) RETURNING id",
                                           item.author_name, now, now))
    execute sanitize("INSERT INTO work_contributors (work_id, contributor_id, role, display_order, created_at, updated_at) VALUES (?, ?, 'author', 0, ?, ?)",
                     work_id, contributor_id, now, now)
    copy_life_dates(contributor_id, item)
  end

  # The wishlist item's ISFDB author check, onto the contributor — unless
  # the contributor already has one of their own.
  def copy_life_dates(contributor_id, item)
    return unless item.author_checked_at
    return if select_value(sanitize("SELECT 1 FROM contributors WHERE id = ? AND life_checked_at IS NOT NULL", contributor_id))

    execute sanitize("UPDATE contributors SET died_date = ?, life_checked_at = ?, " \
                     "external_ids = CASE WHEN ?::text IS NULL THEN external_ids ELSE jsonb_set(external_ids, '{isfdb}', to_jsonb(?::text)) END " \
                     "WHERE id = ?", item.author_died_date, item.author_checked_at,
                     item.author_isfdb_id&.to_s, item.author_isfdb_id&.to_s, contributor_id)
  end

  def link_series(work_id, series_id, now)
    return if select_value(sanitize("SELECT 1 FROM work_series WHERE work_id = ? AND series_id = ?", work_id, series_id))

    execute sanitize("INSERT INTO work_series (work_id, series_id, created_at, updated_at) VALUES (?, ?, ?, ?)", work_id, series_id, now, now)
  end

  WANT_SQL = <<~SQL.freeze
    INSERT INTO wants (work_id, priority, notes, target_price, printing_override_ids, buy_new_override, seed_isbns,
                       cover_url, external_ids, legacy_wishlist_item_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?::bigint[], ?, ?::varchar[], ?, ?::jsonb, ?, ?, ?) RETURNING id
  SQL

  def insert_want(work_id, item, seeds, now)
    select_value(sanitize(WANT_SQL, work_id, item.priority, item.notes, item.target_price, pg_array(item.printing_override_ids),
                          item.buy_new_override, pg_array(seeds), item.cover_url, (item.external_ids || {}).slice("goodreads").to_json,
                          item.id, now, now))
  end

  # The item's ISFDB printings as the work's provider editions, cover
  # groups carried (as the group's pub id, ProviderEdition's convention).
  # A printing the work already has keeps its row, gaining the cover group.
  def copy_printings(work_id, item_id, now)
    execute sanitize(<<~SQL, work_id, now, now, item_id)
      INSERT INTO provider_editions (work_id, provider, provider_id, isbn13, isbn10, publisher, binding, publish_date,
                                     cover_url, cover_artist, cover_group, created_at, updated_at)
      SELECT ?, 'isfdb', isfdb_pub_id::text, isbn13, isbn10, publisher, binding, publish_date,
             cover_url, cover_artist, cover_group::text, ?, ?
        FROM wishlist_printings WHERE wishlist_item_id = ?
      ON CONFLICT (work_id, provider, provider_id) DO UPDATE
        SET cover_group = COALESCE(provider_editions.cover_group, EXCLUDED.cover_group)
    SQL
  end

  # So the next refresh doesn't re-fetch what the wishlist already had.
  def record_refresh(work_id, item, seeds)
    return unless item.printings_refreshed_at

    execute sanitize(<<~SQL, work_id, item.printings_refreshed_at, pg_array(seeds))
      INSERT INTO provider_edition_refreshes (work_id, provider, refreshed_at, queried_isbns)
      VALUES (?, 'isfdb', ?, ?::varchar[]) ON CONFLICT (work_id, provider) DO NOTHING
    SQL
  end

  def short(title) = I18n.transliterate(title.to_s.split(/[:(]/).first.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip

  def pg_array(values) = values.nil? ? nil : "{#{values.join(',')}}"

  def sanitize(sql, *binds) = ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
end

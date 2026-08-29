# Goodreads::ShelfSync#link_shelves used to turn the RSS <user_shelves>
# status shelf (currently-reading, to-read, ...) into a literal Tag on
# any book it auto-created, which then rendered as a lozenge on the work
# page forever. The code no longer does this (STATUS_SHELVES is skipped);
# this clears the tags it already created. Irreversible — these tags were
# never meaningful.
class RemoveStatusShelfTags < ActiveRecord::Migration[8.1]
  STATUS_SHELVES = %w[to-read currently-reading read did-not-finish wishlist].freeze

  def up
    ids = select_values(
      "SELECT id FROM tags WHERE name IN (#{STATUS_SHELVES.map { |s| quote(s) }.join(',')})"
    )
    return if ids.empty?

    execute("DELETE FROM work_tags WHERE tag_id IN (#{ids.join(',')})")
    execute("DELETE FROM tags WHERE id IN (#{ids.join(',')})")
  end

  def down
    # no-op — nothing to restore
  end
end

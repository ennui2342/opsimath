# A cache of `:thumb`-variant bytes, keyed by the variant's Active Storage
# blob key (stable until the cover is replaced). Lets
# Mobile::SnapshotBuilder read every thumbnail in one query instead of
# one blob download each — the download is slow, scales with the whole
# library, and re-fetches bytes that almost never changed since the last
# build. Populated incrementally by `rake mobile:warm_thumbs`; a miss at
# build time falls back to a direct download and caches the result.
#
# Pure derived data — safe to truncate; it refills on the next warm/build.
class MobileThumb < ApplicationRecord
  self.primary_key = :blob_key

  # {blob_key => bytes} for the keys we have cached. One query.
  def self.fetch(keys)
    where(blob_key: keys).pluck(:blob_key, :data).to_h
  end

  def self.store(key, bytes)
    return if key.blank?

    upsert(
      { blob_key: key, data: bytes, byte_size: bytes.bytesize, created_at: Time.current },
      unique_by: :blob_key
    )
  end

  # Populate the cache from an existing snapshot file — it already holds
  # every thumbnail we've put in one, as BLOBs. One ~15 MB file read
  # instead of thousands of per-blob reads off a slow storage volume.
  # A cover that changed since that snapshot just isn't matched here and
  # falls through to a live blob read at build time. Returns the count.
  def self.seed_from_snapshot(snapshot = MobileSnapshot.current)
    return 0 unless snapshot&.file&.attached?

    editions, wishlist = read_snapshot_thumbs(snapshot)
    rows = keyed_rows(Edition, editions) + keyed_rows(WishlistItem, wishlist)
    rows.uniq! { |r| r[:blob_key] }
    upsert_all(rows, unique_by: :blob_key) if rows.any?
    rows.size
  end

  # {record id => thumb bytes} from the snapshot's `editions` and
  # (`kind='wishlist'`) `entries` tables.
  def self.read_snapshot_thumbs(snapshot)
    require "sqlite3"
    require "tempfile"
    Tempfile.create(%w[thumb-seed .sqlite3]) do |file|
      file.binmode
      file.write(snapshot.file.download)
      file.flush

      db = SQLite3::Database.new(file.path)
      editions = db.execute("SELECT id, thumb FROM editions WHERE thumb IS NOT NULL").to_h
      wishlist = db.execute("SELECT id, thumb FROM entries WHERE kind = 'wishlist' AND thumb IS NOT NULL")
                   .to_h { |id, bytes| [ id.delete_prefix("wishlist:").to_i, bytes ] }
      db.close
      [ editions, wishlist ]
    end
  end
  private_class_method :read_snapshot_thumbs

  # Re-key {record id => bytes} by each record's :thumb variant blob key —
  # DB-only lookups, no storage I/O.
  def self.keyed_rows(model, thumbs_by_id)
    return [] if thumbs_by_id.empty?

    model.where(id: thumbs_by_id.keys).includes(cover_image_attachment: :blob).filter_map do |record|
      bytes = thumbs_by_id[record.id]
      { blob_key: record.cover_image.variant(:thumb).processed.key,
        data: bytes, byte_size: bytes.bytesize, created_at: Time.current }
    rescue StandardError => e
      Rails.logger.warn("mobile thumb seed: #{model}##{record.id} — #{e.message}")
      nil
    end
  end
  private_class_method :keyed_rows
end

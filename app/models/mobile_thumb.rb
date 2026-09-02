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
end

# The current offline snapshot the shop-lookup PWA downloads
# (docs/MOBILE.md). Kept as a single row, updated in place — history
# isn't worth the accumulated blobs for a file rebuilt nightly. `version`
# increments on every rebuild; the client polls it to decide whether to
# re-download.
class MobileSnapshot < ApplicationRecord
  has_one_attached :file

  # The one row, created on first rebuild.
  def self.current
    order(:version).last
  end

  def self.regenerate!(isfdb: nil)
    next_version = (current&.version || 0) + 1
    build = Mobile::SnapshotBuilder.build(version: next_version, isfdb:)

    snapshot = current || new
    snapshot.update!(
      version: next_version,
      generated_at: build.generated_at,
      byte_size: build.byte_size,
      entry_count: build.entry_count
    )
    snapshot.file.attach(
      io: build.io, filename: "snapshot-#{next_version}.sqlite3",
      content_type: "application/vnd.sqlite3"
    )
    snapshot
  ensure
    build&.io&.close
  end
end

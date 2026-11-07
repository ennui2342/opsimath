# Rebuilds the offline shop-lookup snapshot and bumps its version
# (docs/MOBILE.md). Scheduled nightly in config/recurring.yml; the data
# only changes via the hourly Goodreads sync, so daily is plenty.
class MobileSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    snapshot = MobileSnapshot.regenerate!
    CatalogueEvent.record(kind: "snapshot", origin: "mobile_snapshot", summary: "Phone app data rebuilt: version #{snapshot.version}, #{snapshot.entry_count} books")
    Rails.logger.info(
      "mobile snapshot v#{snapshot.version}: #{snapshot.entry_count} entries, #{snapshot.byte_size} bytes"
    )
    snapshot
  end
end

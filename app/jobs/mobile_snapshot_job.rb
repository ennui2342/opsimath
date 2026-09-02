# Rebuilds the offline shop-lookup snapshot and bumps its version
# (docs/MOBILE.md). Scheduled nightly in config/recurring.yml; the data
# only changes via the hourly Goodreads sync, so daily is plenty.
class MobileSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    snapshot = MobileSnapshot.regenerate!(isfdb: isfdb_client)
    Rails.logger.info(
      "mobile snapshot v#{snapshot.version}: #{snapshot.entry_count} entries, #{snapshot.byte_size} bytes"
    )
    snapshot
  end

  private

  # Widens the snapshot's ISBN index with siblings from ISFDB (see
  # Mobile::SnapshotBuilder). A missing ISFDB_ADAPTER_URL isn't fatal —
  # the snapshot still builds, just without sibling ISBNs.
  def isfdb_client
    Isfdb::Client.new
  rescue KeyError
    nil
  end
end

# Keeps ProviderEdition current — the editions ISFDB knows for each
# catalogued work, which Mobile::SnapshotBuilder reads for "you own a
# different edition" scan resolution (docs/CATALOG.md, "Architecture
# review"). Scheduled daily ahead of MobileSnapshotJob (config/recurring.yml);
# most works are skipped each run (still fresh), so steady-state cost is small.
class WorkKnownEditionsRefreshJob < ApplicationJob
  queue_as :default

  def perform
    result = Isfdb::WorkKnownEditionsRefresh.run
    Rails.logger.info("known editions refresh: #{result}")
    result
  end
end

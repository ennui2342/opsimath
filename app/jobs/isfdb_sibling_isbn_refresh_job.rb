# Keeps WorkSiblingIsbns current — the cache Mobile::SnapshotBuilder reads
# for "you own a different edition" scan resolution. Scheduled daily
# ahead of MobileSnapshotJob (config/recurring.yml); most works are
# skipped each run (still fresh), so steady-state cost is small.
class IsfdbSiblingIsbnRefreshJob < ApplicationJob
  queue_as :default

  def perform
    result = Isfdb::SiblingIsbnRefresh.run
    Rails.logger.info("sibling ISBN refresh: #{result}")
    result
  end
end

# Keeps ProviderEdition current — the editions every provider knows for
# each catalogued work (ISFDB, Open Library), which Mobile::SnapshotBuilder
# reads for "you own a different edition" scan resolution and the edition
# picker will offer (docs/CATALOG.md). Scheduled daily ahead of
# MobileSnapshotJob (config/recurring.yml); only due works are fetched, so
# steady-state cost is small.
class WorkKnownEditionsRefreshJob < ApplicationJob
  queue_as :default

  def perform
    results = KnownEditionsRefresh.run_all
    results.each { |r| Rails.logger.info("known editions refresh: #{r}") }
    Rails.logger.info("authors linked to ISFDB through their books: #{AuthorLinks.run}")
    results.join("; ")
  end
end

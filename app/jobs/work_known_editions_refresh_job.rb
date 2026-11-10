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
    # Books into their ISFDB series, from the printings just fetched — Mark
    # saw the dry run (443 books, 2026-11-09) and asked for it nightly.
    Rails.logger.info("series from ISFDB: #{WorkSeriesSync.run} books filed")
    # Books take ISFDB's main title (Mark, 2026-11-10): the kinds in
    # TitleCleanup::AUTOMATIC nightly; the rest wait in Settings → Titles
    # to review.
    Rails.logger.info("ISFDB main titles fetched: #{Isfdb::MainTitles.run}")
    Rails.logger.info("titles from ISFDB: #{TitleCleanup.apply} books retitled; #{TitleCleanup.ask} questions asked")
    Rails.logger.info("authors linked to ISFDB through their books: #{AuthorLinks.run}")
    results.join("; ")
  end
end

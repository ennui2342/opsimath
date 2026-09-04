namespace :isfdb do
  desc "Enrich Editions with real bibliographic data via isfdb-adapter (ISBN-based; see docs/INTEGRATIONS.md)"
  task enrich_editions: :environment do
    counts = IsfdbEnrichmentJob.perform_now
    puts counts
  end

  desc "Re-fetch every ISBN-bearing Edition from isfdb-adapter, including ones already enriched — for a change that only reaches an edition on its next real fetch (a new field, a looser apply rule)"
  task reenrich_editions: :environment do
    counts = IsfdbEnrichmentJob.perform_now(force: true)
    puts counts
  end
end

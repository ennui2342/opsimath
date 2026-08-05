namespace :isfdb do
  desc "Enrich Editions with real bibliographic data via isfdb-adapter (ISBN-based; see docs/INTEGRATIONS.md)"
  task enrich_editions: :environment do
    counts = IsfdbEnrichmentJob.perform_now
    puts counts
  end
end

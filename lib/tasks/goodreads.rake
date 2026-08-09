namespace :goodreads do
  desc "Phase 1 bulk import of a Goodreads library export CSV (see docs/INTEGRATIONS.md)"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path] || Rails.root.join("import/goodreads_library_export_enriched.csv")
    abort "No such file: #{path}" unless File.exist?(path)

    # Always seeded first, not just documented as a manual prerequisite —
    # skipping Genre seeding silently changes import results (every
    # Bookshelves label lands as a Tag instead), exactly the kind of
    # easy-to-forget sequencing step that shouldn't rely on a human
    # remembering it. db/seeds.rb is idempotent, so this costs nothing on
    # a repeat run.
    Rake::Task["db:seed"].invoke

    counts = Goodreads::Importer.import(path)
    puts counts
  end

  desc "Phase 2 ongoing sync against the live Goodreads RSS feeds (see docs/INTEGRATIONS.md)"
  task sync: :environment do
    counts = GoodreadsSyncJob.perform_now
    puts counts
  end

  desc "Wipe all book/reading/review/enrichment data and rebuild it from source (CSV import + Goodreads sync + ISFDB enrichment). Never run automatically — requires CONFIRM=yes. Pass SKIP_SYNC=yes to omit the Goodreads RSS sync step (CSV import + ISFDB enrichment only — e.g. for a restore-point dump that shouldn't carry any RSS-sourced data)."
  task rebuild: :environment do
    abort "Refusing to run without CONFIRM=yes" unless ENV["CONFIRM"] == "yes"

    ActiveRecord::Base.connection.tables.each do |table|
      next if %w[users sessions api_tokens schema_migrations ar_internal_metadata].include?(table)
      next if table.start_with?("solid_queue_", "solid_cache_")

      ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{ActiveRecord::Base.connection.quote_table_name(table)} RESTART IDENTITY CASCADE")
    end

    Rake::Task["goodreads:import"].invoke # also reseeds Genre/Subject (db/seeds.rb) — same as every normal import run
    Rake::Task["goodreads:sync"].invoke unless ENV["SKIP_SYNC"] == "yes" # GoodreadsSyncState is wiped too, so this is a genuine first-ever full backfill
    Rake::Task["isfdb:enrich_editions"].invoke
  end
end

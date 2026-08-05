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
end

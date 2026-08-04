namespace :goodreads do
  desc "Phase 1 bulk import of a Goodreads library export CSV (see docs/INTEGRATIONS.md)"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path] || Rails.root.join("import/goodreads_library_export_enriched.csv")
    abort "No such file: #{path}" unless File.exist?(path)

    counts = Goodreads::Importer.import(path)
    puts counts
  end
end

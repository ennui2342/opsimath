namespace :misfiled_artists do
  # Cover artists the Goodreads import recorded as co-authors (MisfiledArtistCleanup).
  desc "Dry run unless APPLY=1"
  task cleanup: :environment do
    fixes = MisfiledArtistCleanup.plan
    fixes.group_by(&:reason).each do |reason, fs|
      puts "#{reason}: #{fs.size}"
      fs.first(ENV.fetch("EXAMPLES", 6).to_i).each { |f| puts "  #{f.work_contributor.work.title.truncate(40)} — #{f.work_contributor.contributor.name}#{' (+ edition cover artist)' if f.fill_editions.any?}" }
    end
    puts "applied: #{MisfiledArtistCleanup.apply} credits moved" if ENV["APPLY"] == "1"
  end
end

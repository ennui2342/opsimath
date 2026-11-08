namespace :titles do
  # Goodreads' bracketed series/imprint text on titles (TitleCleanup).
  desc "Dry run unless APPLY=1"
  task cleanup: :environment do
    fixes, rest = TitleCleanup.plan
    puts "to retitle from ISFDB: #{fixes.size}"
    fixes.each { |f| puts "  #{f.from}  ->  #{f.to}" }
    puts "left alone (no matching ISFDB title): #{rest.size}"
    rest.each { |w| puts "  #{w.title}" }
    puts "applied: #{TitleCleanup.apply} books retitled" if ENV["APPLY"] == "1"
  end
end

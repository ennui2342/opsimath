namespace :titles do
  # Books' titles against ISFDB's (TitleCleanup). Brackets and cosmetic
  # differences are applied nightly; this is the dry run, or APPLY=1 now.
  desc "Dry run unless APPLY=1"
  task cleanup: :environment do
    TitleCleanup.plan.group_by(&:kind).each do |kind, fixes|
      puts "#{kind}: #{fixes.size}#{' (review only)' unless TitleCleanup::AUTOMATIC.include?(kind)}"
      fixes.first(ENV.fetch("EXAMPLES", 10).to_i).each { |f| puts "  #{f.from}  ->  #{f.to}" }
    end
    puts "applied: #{TitleCleanup.apply} books retitled" if ENV["APPLY"] == "1"
  end
end

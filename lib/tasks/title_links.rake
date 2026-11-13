namespace :title_links do
  # Extra ISFDB title links that are a different work (TitleLinkPrune).
  desc "Dry run unless APPLY=1; EXAMPLES=n"
  task prune: :environment do
    plan = TitleLinkPrune.plan
    puts "books with links to drop: #{plan.size} (#{plan.sum { |p| p.drop.size }} links)"
    plan.first(ENV.fetch("EXAMPLES", 30).to_i).each do |p|
      label = ->(r) { "#{r.dig('main', 'title')} #{r.dig('main', 'type')} #{r.dig('main', 'year')}" }
      puts "  #{p.work.title.truncate(40)} — keep #{label.(p.keep)}; drop #{p.drop.map { |_, r| label.(r) }.join(' | ')}"
    end
    puts "applied: #{TitleLinkPrune.apply} links dropped" if ENV["APPLY"] == "1"
  end
end

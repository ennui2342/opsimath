namespace :authors do
  # Book authors checked against ISFDB's title credits (AuthorCleanup).
  desc "Dry run unless APPLY=1; EXAMPLES=n per kind"
  task cleanup: :environment do
    n = ENV.fetch("EXAMPLES", 10).to_i
    merges, changes = AuthorCleanup.plan
    puts "people merged (the same person twice): #{merges.size}"
    merges.first(n).each { |m| puts "  #{m.keep.name} ← #{m.drop.map(&:name).join(', ')}" }
    { demote: "now a contributor, not an author", remove: "mangled name removed", add: "ISFDB author added" }.each do |kind, label|
      hits = changes.select { |c| c.public_send(kind).any? }
      puts "#{label}: #{hits.sum { |c| c.public_send(kind).size }} on #{hits.size} books"
      hits.first(n).each do |c|
        names = c.public_send(kind).map { |x| x.is_a?(Array) ? x.first : x.name }
        puts "  #{c.work.title.truncate(45)} — #{names.first(6).join(', ')}#{" +#{names.size - 6}" if names.size > 6}"
      end
    end
    puts "ISFDB ids linked: #{changes.sum { |c| c.link.size }}"
    puts "applied: %d people merged, %d books changed" % AuthorCleanup.apply if ENV["APPLY"] == "1"
  end
end

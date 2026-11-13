namespace :works do
  # Books in the catalogue twice: sharing an ISFDB title link.
  desc "List books that share an ISFDB title"
  task duplicates: :environment do
    WorkIdentifier.where(id_type: "isfdb_title").group(:value).having("count(DISTINCT work_id) > 1").pluck(:value).each do |value|
      works = Work.joins(:work_identifiers).where(work_identifiers: { id_type: "isfdb_title", value: }).includes(:want, :readings, editions: :copies).distinct
      puts "ISFDB #{value}: " + works.map { |w|
        "##{w.id} #{w.title} (#{w.editions.size} ed#{', owned' if w.editions.any? { |e| e.copies.any?(&:owned?) }}, #{w.readings.size} reads#{', wanted' if w.want})"
      }.join(" | ")
    end
  end

  # WorkMerge: KEEP=id DROP=id; a dry run unless APPLY=1.
  desc "Merge book DROP into KEEP (APPLY=1)"
  task merge: :environment do
    keep = Work.find(ENV.fetch("KEEP"))
    drop = Work.find(ENV.fetch("DROP"))
    puts "keep ##{keep.id} #{keep.title} ← ##{drop.id} #{drop.title} (#{drop.editions.count} editions, #{drop.readings.count} readings, #{drop.want ? 'wanted' : 'not wanted'})"
    [ keep, drop ].each { |w| puts "  ##{w.id}'s editions are printings of ISFDB titles #{WorkMerge.edition_titles(w).to_a.inspect}" }
    next unless ENV["APPLY"] == "1"

    WorkMerge.merge!(keep:, drop:, force: ENV["FORCE"] == "1")
    puts "merged"
  end
end

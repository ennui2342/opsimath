namespace :works do
  # Books in the catalogue twice: sharing an ISFDB title link.
  desc "List books that share an ISFDB title"
  # By the ISFDB title records their editions' publications belong to —
  # not shared ISFDB links, which led to merging Peace and War (an omnibus)
  # into The Forever War (2026-11-13).
  task duplicates: :environment do
    by_record = Work.where(id: EditionContent.select(:work_id)).find_each.each_with_object(Hash.new { |h, k| h[k] = [] }) do |w, out|
      WorkMerge.edition_titles(w).each { |id| out[id] << w.id }
    end
    by_record.select { |_, ids| ids.uniq.size > 1 }.each do |value, ids|
      works = Work.where(id: ids.uniq).includes(:want, :readings, editions: :copies)
      puts "ISFDB title record #{value}: " + works.map { |w|
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

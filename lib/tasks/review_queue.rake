namespace :review_queue do
  # docs/CATALOG.md "Anchored editions" → "The existing queue".
  # Dry run by default: counts, and examples per action. APPLY=1 applies.
  desc "ISFDB wins for editions anchored to an ISFDB printing (dry run unless APPLY=1)"
  task isfdb_wins: :environment do
    outcomes = ReviewQueue::IsfdbWins.plan
    outcomes.group_by(&:action).each do |action, os|
      puts "#{action}: #{os.size}"
      os.first(ENV.fetch("EXAMPLES", 6).to_i).each do |o|
        e = o.decision.entity
        puts "  ##{o.decision.id} #{e.respond_to?(:works) ? e.works.first&.title : '?'} — #{o.reason}"
      end
    end
    if ENV["APPLY"] == "1"
      ReviewQueue::IsfdbWins.apply
      puts "applied; pending now #{PendingDecision.pending.count}"
    end
  end
end

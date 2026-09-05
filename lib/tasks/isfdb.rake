namespace :isfdb do
  desc "Enrich Editions with real bibliographic data via isfdb-adapter (ISBN-based; see docs/INTEGRATIONS.md)"
  task enrich_editions: :environment do
    counts = IsfdbEnrichmentJob.perform_now
    puts counts
  end

  desc "Re-fetch every ISBN-bearing Edition from isfdb-adapter, including ones already enriched — for a change that only reaches an edition on its next real fetch (a new field, a looser apply rule)"
  task reenrich_editions: :environment do
    counts = IsfdbEnrichmentJob.perform_now(force: true)
    puts counts
  end

  desc "Re-evaluate every pending enrichment_printing_choice decision against IsfdbEditionEnricher#same_edition? and auto-accept the ones that turn out to be duplicate ISFDB records for the same real printing (no new isfdb-adapter fetch — the candidates are already on the decision)"
  task resolve_duplicate_printings: :environment do
    resolved = 0
    left = 0
    PendingDecision.pending.where(kind: "enrichment_printing_choice").find_each do |pending_decision|
      edition = pending_decision.entity
      candidates = pending_decision.payload["candidates"] || []
      winner = edition && Enrichment::IsfdbEditionEnricher.resolve_candidate_for(edition, candidates)
      if winner
        Enrichment::PendingDecisionResolver.accept(pending_decision, pub_id: winner["_isfdb_pub_id"].to_s)
        resolved += 1
      else
        left += 1
      end
    end
    puts "resolved=#{resolved} left=#{left}"
  end

  desc "Reconciles every enrichment_printing_choice decision a sweep (or a human) has ever resolved against the current same_edition? — in either direction. Needed twice on 2026-09-05: once for the field-coverage fix (title_id/authors/series_id/cover_artists/year/language, not just binding/publisher/page_count), then again for an Array#one?-on-nil bug that wrongly reopened some already-correct merges. Only touches a decision whose edition already has an isfdb EnrichmentRecord matching one of its own candidates (i.e., something was actually resolved before) — a genuinely never-touched pending decision is left alone regardless of what same_edition? says now. See docs/INTEGRATIONS.md"
  task reconcile_printing_merges: :environment do
    reopened = 0
    reclosed = 0
    PendingDecision.where(kind: "enrichment_printing_choice").find_each do |pending_decision|
      edition = pending_decision.entity
      next unless edition

      candidates = pending_decision.payload["candidates"] || []
      pub_ids = candidates.map { |c| c["_isfdb_pub_id"].to_s }
      next unless EnrichmentRecord.where(entity: edition, provider: "isfdb", external_id: pub_ids).exists?

      correct_status = Enrichment::IsfdbEditionEnricher.same_edition_for?(candidates) ? "accepted" : "pending"
      next if pending_decision.status == correct_status

      pending_decision.update!(status: correct_status, resolved_at: correct_status == "accepted" ? Time.current : nil)
      correct_status == "accepted" ? (reclosed += 1) : (reopened += 1)
    end
    puts "reopened=#{reopened} reclosed=#{reclosed}"
  end
end

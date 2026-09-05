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

  desc "One-time remediation for the 2026-09-05 same_edition? audit: reopen every accepted enrichment_printing_choice decision the corrected algorithm (title_id/authors/series_id/cover_artists/year/language, not just binding/publisher/page_count) would NOT have merged — see docs/INTEGRATIONS.md. Leaves the currently-applied field values in place; reopening puts it back in front of a human, same as any other pending decision"
  task reopen_bad_printing_merges: :environment do
    reopened = 0
    kept = 0
    PendingDecision.where(kind: "enrichment_printing_choice", status: "accepted").find_each do |pending_decision|
      candidates = pending_decision.payload["candidates"] || []
      if Enrichment::IsfdbEditionEnricher.same_edition_for?(candidates)
        kept += 1
      else
        pending_decision.update!(status: "pending", resolved_at: nil)
        reopened += 1
      end
    end
    puts "reopened=#{reopened} kept=#{kept}"
  end
end

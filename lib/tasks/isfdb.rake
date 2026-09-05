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
      if correct_status == "accepted"
        reclosed += 1
      else
        # Reopening puts this back in front of a human — but accepting it
        # the first time purged its candidate_covers (no longer needed
        # once resolved), and nothing about "this needs review again"
        # implies a fresh fetch, so without this the review screen would
        # show every candidate with no cover at all. Real gap found live
        # 2026-09-05 — see isfdb:backfill_printing_choice_covers, which
        # this duplicates inline so a future reopen doesn't need a
        # separate manual step to notice and fix it again.
        Enrichment::IsfdbEditionEnricher.attach_candidate_covers_for(pending_decision, candidates)
        reopened += 1
      end
    end
    puts "reopened=#{reopened} reclosed=#{reclosed}"
  end

  desc "Re-downloads candidate cover images for pending enrichment_printing_choice decisions that are missing them — accepting a decision purges candidate_covers (no longer needed once resolved), but reopening one back to pending (isfdb:reconcile_printing_merges, before it did this inline) never re-fetched them. Safe to re-run — skips a decision that already has every cover it can get (mirrors IsfdbEditionEnricher#attach_candidate_covers' own dedup)"
  task backfill_printing_choice_covers: :environment do
    touched = 0
    PendingDecision.pending.where(kind: "enrichment_printing_choice").find_each do |pending_decision|
      candidates = pending_decision.payload["candidates"] || []
      before = pending_decision.candidate_covers.count
      Enrichment::IsfdbEditionEnricher.attach_candidate_covers_for(pending_decision, candidates)
      touched += 1 if pending_decision.candidate_covers.count > before
    end
    puts "backfilled=#{touched}"
  end

  desc "Resolves a pending enrichment_conflict that a co-located enrichment_printing_choice for the same entity+source supersedes — the printing choice's own flag/accept now does this prospectively (IsfdbEditionEnricher#supersede_field_conflicts, PendingDecisionResolver#resolve_superseded_conflict); this catches ones from before those existed. A *pending* printing choice supersedes unconditionally (its screen covers every field a conflict can dispute); an *accepted* one only if every disputed field already carries field_sources[field] == source on the entity — real proof an isfdb write reached it, not an assumption about what a past accept covered. Safe to re-run"
  task resolve_superseded_conflicts: :environment do
    resolved = 0
    covered_fields = PendingDecision::EDITION_FIELD_ORDER + %w[cover_image]

    PendingDecision.where(kind: "enrichment_printing_choice").find_each do |printing_choice|
      entity_type = printing_choice.payload["entity_type"]
      entity_id = printing_choice.payload["entity_id"]
      source = printing_choice.payload["source"]
      conflict = PendingDecision.pending.where(kind: "enrichment_conflict")
                                 .where("payload @> ?", { "entity_type" => entity_type, "entity_id" => entity_id, "source" => source }.to_json)
                                 .first
      next unless conflict

      record = conflict.entity
      next unless record

      disputed = conflict.payload["fields"] || []
      supersedes =
        if printing_choice.pending?
          disputed.all? { |f| covered_fields.include?(f) }
        else
          disputed.all? { |f| record.field_sources[f] == source }
        end
      next unless supersedes

      conflict.update!(status: "accepted", resolved_at: Time.current)
      resolved += 1
    end
    puts "resolved=#{resolved}"
  end
end

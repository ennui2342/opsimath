module Enrichment
  # The one place that decides what to do with a source's proposed
  # fields, and the one place that does it — deliberately entity-agnostic
  # (Edition today, but nothing here assumes it) and source-agnostic
  # (Goodreads CSV import, Goodreads RSS sync, and ISFDB enrichment all
  # route through the same #integrate, not three separate reimplementations
  # of it). Mark, 2026-08-08: "we're seeing records coming in as
  # additional metadata from an enrichment source and they should follow
  # the same process no matter whether they're a Goodreads source from
  # the RSS or an ISFDB source" — before this, IsfdbEditionEnricher had
  # its own bundle-or-commit orchestration that Goodreads' path never
  # got, so the identical event (a cover conflicting with what's on file)
  # produced a differently-shaped PendingDecision depending on which
  # source raised it. One kind now ("enrichment_conflict"), one mechanism.
  #
  # #record is the convenience entry point for the common case — a
  # source with no field-specific judgment calls to make (Goodreads:
  # every field is a plain fill/conflict, no ISFDB-style substring/EDTF
  # refinement logic) — it plans every field generically and integrates
  # them. A source that DOES have real per-field judgment calls (ISFDB's
  # publisher substring-variant handling, its EDTF-precision publish_date
  # handling) builds its own plans and calls #integrate directly instead
  # — the shared part is the *decision* (bundle vs. commit), never the
  # per-field planning logic itself, which stays wherever it's actually
  # informed by that source's real data quirks.
  module SourceRecorder
    # One EnrichmentRecord per (entity, provider) — found and updated in
    # place, not always created fresh. Mark, 2026-08-09: "if a new
    # publisher comes in from an enrichment source for an existing
    # entity... it should overwrite the old [value in the record]. And
    # then that record, because it's had a change, should be running
    # through the standard workflow." So a same-provider field update
    # overwrites unconditionally at the EnrichmentRecord layer (this is
    # one provider updating its own belief, not two providers
    # disagreeing — nothing to reconcile at this layer), and it's *only*
    # the fields this fetch actually mentions that get (re-)planned
    # against the entity below — a field this provider already reported
    # earlier and isn't repeating now stays as recorded, untouched, and
    # doesn't get re-integrated.
    def self.record(entity:, provider:, external_id:, raw_payload:, fields: {})
      record = EnrichmentRecord.find_or_initialize_by(entity: entity, provider: provider)
      record.update!(
        external_id: external_id, fetched_at: Time.current, raw_payload: raw_payload,
        fields: record.fields.merge(fields.stringify_keys)
      )
      record.attach_cover_from_url(fields[:cover_image])

      # cover_image can't go through FieldApplier.plan — it's an
      # attachment, not a plain column — so CoverApplier plans it
      # separately using the copy #attach_cover_from_url just downloaded.
      plans = fields.filter_map { |field, value| FieldApplier.plan(entity, field, value, provider) unless field == :cover_image }
      plans << CoverApplier.plan(entity, record.cover_image, provider) if record.cover_image.attached?

      integrate(plans, entity: entity, provider: provider)
      record
    end

    # Plans every candidate field before committing any of them. A blank
    # destination field isn't proof this fetch is safe to trust — the
    # fetch could be describing a different specific printing entirely
    # (isfdb-adapter's own documented caveat: one ISBN can be reused
    # across distinct print runs), and that's exactly the kind of thing a
    # human looking at the full comparison (cover included) can judge for
    # themselves but this code can't. So the instant *any* field from
    # this fetch is a genuine :conflict, nothing from the fetch commits
    # silently — every field it proposed (fills and refinements too)
    # goes into one bundled review decision, offered piecemeal (checked
    # by default — accepting all of them reproduces the auto-fill
    # outcome, but the reviewer can now see the whole record first and
    # uncheck anything that looks like it belongs to a different edition
    # instead of trusting it sight unseen). Mark, 2026-08-08.
    #
    # A lone :refine carries no such risk (it's the same fact restated
    # more precisely, not a disagreement), so with no real :conflict
    # present, fills and refinements alike still commit immediately.
    def self.integrate(plans, entity:, provider:)
      if plans.any? { |p| p.action == :conflict }
        create_bundled_decision(plans.select { |p| %i[fill refine conflict].include?(p.action) }, entity: entity, provider: provider)
      else
        plans.select { |p| %i[fill refine].include?(p.action) }.each { |p| commit_plan(p) }
        resolve_stale_conflict(entity: entity, provider: provider)
      end
    end

    # A fetch that commits cleanly here might be re-processing an entity
    # that already has an *older* enrichment_conflict decision sitting in
    # the queue from a previous, genuinely-conflicting fetch (or from a
    # since-loosened rule — CoverApplier's `authoritative:` cover trust,
    # 2026-09-04, is exactly this: yesterday's cover byte-difference
    # conflict is today's silent fill). Leaving that old decision pending
    # would ask a human to review a disagreement that no longer exists —
    # its fields already match what's now on file. Close it the same way
    # a human accepting it would (status: "accepted"), not silently
    # delete it — the record of what was proposed and resolved stays.
    def self.resolve_stale_conflict(entity:, provider:)
      existing = PendingDecision.pending.where(kind: "enrichment_conflict")
                                 .where("payload @> ?", { entity_type: entity.class.name, entity_id: entity.id, source: provider }.to_json)
                                 .first
      existing&.update!(status: "accepted", resolved_at: Time.current)
    end
    private_class_method :resolve_stale_conflict

    # :fill and :refine commit identically (write the value, record
    # field_sources) — the distinction only matters to the caller
    # deciding *whether* to commit a given plan, not to how a
    # decided-safe write is performed. cover_image can't share the same
    # single #update! call the way a plain column field can (confirmed
    # directly: mixing an attachment assignment into the same #update!
    # as other columns doesn't reliably work), so it gets its own branch.
    def self.commit_plan(plan)
      if plan.field == :cover_image
        plan.record.cover_image.attach(plan.value)
        plan.record.update!(field_sources: plan.record.field_sources.merge("cover_image" => plan.source))
      else
        plan.record.update!(plan.field => plan.value, field_sources: plan.record.field_sources.merge(plan.field.to_s => plan.source))
      end
    end

    # The "review this record" bundle. Find-or-create (not a plain
    # create) so re-enriching an entity that already has an unresolved
    # conflict reuses the same decision instead of spawning a second one
    # alongside it.
    def self.create_bundled_decision(plans, entity:, provider:)
      fields = plans.map { |p| p.field.to_s }
      # Always offer the cover here too, even when its own plan concluded
      # :unchanged (checksums matched) or wasn't part of the conflict at
      # all — we don't currently have a reliable way to tell "genuinely
      # different cover" from "same cover, different bytes," so rather
      # than silently trust either answer, the review screen always gets
      # the option when this source has one on file (Mark, 2026-08-08).
      latest = EnrichmentRecord.latest(entity: entity, provider: provider)
      fields |= [ "cover_image" ] if latest&.cover_image&.attached?

      existing = PendingDecision.where(kind: "enrichment_conflict", status: "pending")
                                 .where("payload @> ?", { entity_type: entity.class.name, entity_id: entity.id, source: provider }.to_json)
                                 .first
      return existing if existing

      PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: {
          "entity_type" => entity.class.name,
          "entity_id" => entity.id,
          "source" => provider,
          "fields" => fields
        }
      )
    end
  end
end

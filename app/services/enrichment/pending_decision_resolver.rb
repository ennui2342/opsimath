module Enrichment
  # Applies (accept) or discards (reject) a PendingDecision — the first
  # real code path for the "manual edit"/human-review half of
  # DATA_MODEL.md's EnrichmentRecord policy (Enrichment::FieldApplier
  # only ever *creates* these; nothing resolved them until now).
  #
  # Both real kinds' payloads point at an Edition (ISFDB enrichment is
  # edition-scoped only, per IsfdbEditionEnricher's own comment).
  # Reuses PendingDecision#field_diffs (the same display-shaped view the
  # review-queue UI renders) rather than re-parsing the two payload
  # shapes independently — a bundled enrichment_edition_mismatch's
  # several fields and an isolated enrichment_field_conflict's one both
  # arrive here identically shaped.
  #
  # A kind with no known automatic action (e.g. reread_conflict — zero
  # real instances as of this writing, and its correct "accept" means
  # opening a Reading, not applying a field) has an empty
  # `field_diffs`, so accept/reject then only changes
  # PendingDecision#status, never mutating an entity it doesn't
  # understand.
  class PendingDecisionResolver
    def self.accept(pending_decision) = new(pending_decision).accept
    def self.reject(pending_decision) = new(pending_decision).reject

    def initialize(pending_decision)
      @pending_decision = pending_decision
    end

    def accept
      record = @pending_decision.entity
      diffs = @pending_decision.field_diffs.select { |d| d[:proposed].present? }
      if record && diffs.any?
        attributes = diffs.to_h { |d| [ d[:field], d[:proposed] ] }
        sources = diffs.to_h { |d| [ d[:field].to_s, d[:source] ] }
        record.update!(attributes.merge(field_sources: record.field_sources.merge(sources)))
      end
      @pending_decision.update!(status: "accepted", resolved_at: Time.current)
    end

    def reject
      @pending_decision.update!(status: "rejected", resolved_at: Time.current)
    end
  end
end

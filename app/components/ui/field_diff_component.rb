module Ui
  # One row of "current -> proposed" for a single field — the visual
  # core of a PendingDecision's detail view. Reused identically for the
  # isolated-conflict payload shape (one row) and the bundled-mismatch
  # shape (several rows) — see Enrichment::PendingDecisionResolver for
  # the two payloads this renders.
  class FieldDiffComponent < ApplicationComponent
    # other_candidates: display-only, from PendingDecision#field_candidates
    # — any other known provider's current value for this field, so a
    # reviewer can see e.g. that two sources actually agree and only a
    # third is the outlier. Never drives accept/reject.
    def initialize(field:, current:, proposed:, source: nil, other_candidates: [])
      @field = field
      @current = current
      @proposed = proposed
      @source = source
      @other_candidates = other_candidates
    end
  end
end

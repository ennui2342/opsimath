module Ui
  # One row of "current -> proposed" for a single field — the visual
  # core of a PendingDecision's detail view. Reused identically for the
  # isolated-conflict payload shape (one row) and the bundled-mismatch
  # shape (several rows) — see Enrichment::PendingDecisionResolver for
  # the two payloads this renders.
  class FieldDiffComponent < ApplicationComponent
    def initialize(field:, current:, proposed:, source: nil, checkbox: false)
      @field = field
      @current = current
      @proposed = proposed
      @source = source
      @checkbox = checkbox
    end
  end
end

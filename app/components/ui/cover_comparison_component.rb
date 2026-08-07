module Ui
  # Current vs. candidate cover, side by side — the primary visual anchor
  # for reviewing an enrichment_edition_mismatch decision. Per Mark's own
  # framing: "does this look like the right edition" is usually decided
  # by the cover before any other field, so this renders above the
  # field-by-field comparison, not alongside it.
  class CoverComparisonComponent < ApplicationComponent
    # other_candidates: display-only, from PendingDecision#field_candidates(:cover_image)
    # — any other known provider's cover URL on file, for the same reason
    # FieldDiffComponent shows them for text fields. Never drives accept/reject.
    def initialize(current:, candidate:, other_candidates: [])
      @current = current
      @candidate = candidate
      @other_candidates = other_candidates
    end
  end
end

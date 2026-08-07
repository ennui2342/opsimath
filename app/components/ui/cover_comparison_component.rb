module Ui
  # Current vs. candidate cover, side by side — the primary visual anchor
  # for reviewing an enrichment_edition_mismatch decision. Per Mark's own
  # framing: "does this look like the right edition" is usually decided
  # by the cover before any other field, so this renders above the
  # field-by-field comparison, not alongside it.
  class CoverComparisonComponent < ApplicationComponent
    def initialize(current:, candidate:)
      @current = current
      @candidate = candidate
    end
  end
end

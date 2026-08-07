module Ui
  # A full "Current" card and a full "Proposed" card side by side, one
  # row per disputed field in each — continues the same visual language
  # as Ui::CoverComparisonComponent above it on the review screen,
  # rather than a flat per-field diff list (see PendingDecisionsController).
  # Per-field checkboxes (checked by default) live on the Proposed side
  # only; the Current side is read-only reference.
  class RecordComparisonComponent < ApplicationComponent
    def initialize(diffs:)
      @diffs = diffs
    end
  end
end

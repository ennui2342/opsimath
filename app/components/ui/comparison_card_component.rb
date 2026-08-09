module Ui
  # One full card in the 3-card enrichment review layout: the Edition's
  # current catalog state, another provider's record on file, or the
  # proposing record that raised the decision. Dumb renderer — all the
  # "which fields, which are selectable, which provider" logic lives in
  # PendingDecision#comparison_cards, which builds the PendingDecision::Card
  # this takes directly.
  class ComparisonCardComponent < ApplicationComponent
    def initialize(card:)
      @card = card
    end
  end
end

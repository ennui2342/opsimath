module Ui
  # One full card in the comparison-review layout, used by every "here are
  # the candidates, make a structural call" screen: the PendingDecision
  # enrichment-conflict review (Edition's catalog state / another provider's
  # record / the proposing record) and the EditionReconciliation review
  # (each owned Edition / the incoming Goodreads row).
  #
  # Dumb renderer — all the "which fields, which are selectable, which
  # provider" logic lives in the model method that builds the Cards
  # (PendingDecision#comparison_cards, EditionReconciliation#comparison_cards).
  #
  # Card knobs:
  # - proposed        — flags the card that raised the decision (conflict ring + header tint)
  # - cover           — an ActiveStorage attachment to show
  # - cover_url       — a remote image URL to show instead (incoming feed rows have no attachment)
  # - cover_selectable — render the "Apply this cover" checkbox on the cover
  # - show_empty_cover — draw the "No cover" placeholder when nothing's attached
  # - fields          — FieldRows; a selectable one gets a checkbox (fields[])
  # - identifiers      — [[label, value], ...] mono footer
  # - info_note        — small muted line at the card foot
  # - select_name / select_value / selected — when select_name is set the whole
  #   card header becomes a radio (picks this card among its siblings); a
  #   checked card takes the same conflict ring as `proposed`.
  class ComparisonCardComponent < ApplicationComponent
    Card = Struct.new(
      :label, :meta, :proposed, :cover, :cover_url, :cover_selectable, :show_empty_cover,
      :fields, :identifiers, :info_note, :select_name, :select_value, :selected,
      keyword_init: true
    )
    FieldRow = Struct.new(:name, :value, :chip, :selectable, keyword_init: true)

    def initialize(card:)
      @card = card
    end
  end
end

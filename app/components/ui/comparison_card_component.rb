module Ui
  # One full card in the comparison-review layout, used by every "here are
  # the candidates, make a structural call" screen: the PendingDecision
  # enrichment-conflict review (Edition's catalog state / another provider's
  # record / the proposing record), the EditionReconciliation review (each
  # owned Edition / the incoming Goodreads row), and the
  # enrichment_printing_choice review (one card per ISFDB printing that
  # shares the ISBN — radio in the header *and* per-field checkboxes).
  #
  # Dumb renderer — all the "which fields, which are selectable, which
  # provider" logic lives in the model method that builds the Cards
  # (PendingDecision#comparison_cards / #printing_choice_cards,
  # EditionReconciliation#comparison_cards).
  #
  # Card knobs:
  # - proposed        — flags the card that raised the decision (conflict ring + header tint)
  # - cover           — an ActiveStorage attachment to show
  # - cover_url       — a remote image URL to show instead (feed rows / un-downloaded candidates)
  # - cover_selectable — render the "Apply this cover" checkbox on the cover
  # - show_empty_cover — draw the "No cover" placeholder when nothing's attached
  # - fields          — FieldRows; a selectable one gets a checkbox (fields[])
  # - identifiers      — [[label, value], ...] mono footer
  # - info_note        — small muted line at the card foot
  # - select_name / select_value / selected — when select_name is set the whole
  #   card header becomes a radio (picks this card among its siblings); a
  #   checked card takes the same conflict ring as `proposed`
  # - input_scope      — prefix for this card's checkbox/radio ids, so N cards
  #   with the same field names don't collide (e.g. "pub123_")
  # - fields_disabled  — render this card's field/cover checkboxes unchecked +
  #   disabled (a printing-choice card whose radio isn't the selected one);
  #   a Stimulus controller flips this as the radio changes
  class ComparisonCardComponent < ApplicationComponent
    Card = Struct.new(
      :label, :meta, :proposed, :cover, :cover_url, :cover_selectable, :show_empty_cover,
      :fields, :identifiers, :info_note, :select_name, :select_value, :selected,
      :input_scope, :fields_disabled,
      keyword_init: true
    )
    FieldRow = Struct.new(:name, :value, :chip, :selectable, keyword_init: true)

    def initialize(card:)
      @card = card
    end

    private

    def field_id(name) = "#{@card.input_scope}field_#{name}"
    def field_checked = !@card.fields_disabled
  end
end

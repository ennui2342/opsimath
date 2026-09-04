module Ui
  # One full card in the comparison-review layout, used by every "here are
  # the candidates, make a structural call" screen: the PendingDecision
  # enrichment-conflict review (Edition's catalog state / another provider's
  # record / the proposing record), the EditionReconciliation review (each
  # owned Edition / the incoming Goodreads row), the
  # enrichment_printing_choice review (one card per ISFDB printing that
  # shares the ISBN — radio in the header *and* per-field checkboxes), and
  # the on-demand edition-metadata screen (one card per known source, every
  # field pickable, mixed freely across sources — Enrichment::EditionMetadataCards).
  #
  # Dumb renderer — all the "which fields, which are selectable, which
  # provider" logic lives in the model method that builds the Cards
  # (PendingDecision#comparison_cards / #printing_choice_cards,
  # EditionReconciliation#comparison_cards, Enrichment::EditionMetadataCards#build).
  #
  # Card knobs:
  # - proposed        — flags the card that raised the decision (conflict ring + header tint)
  # - cover           — an ActiveStorage attachment to show
  # - cover_url       — a remote image URL to show instead (feed rows / un-downloaded candidates)
  # - cover_selectable — render the "Apply this cover" checkbox on the cover
  # - show_empty_cover — draw the "No cover" placeholder when nothing's attached
  # - fields          — FieldRows; a selectable one gets a checkbox (fields[] by default)
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
  # - field_value_prefix — when set, every checkbox in this card submits as
  #   `field_picks[]` = "`<prefix>:<field name>`" instead of `fields[]` =
  #   "`<field name>`" — self-describing picks so a screen with N cards can
  #   mix fields freely across sources (edition-metadata screen: prefix is
  #   the provider). `printing_choice_controller.js`'s sibling,
  #   `field_pick_controller.js`, keeps at most one source checked per field.
  # - fields_start_checked — overrides the default checked state (normally
  #   `!fields_disabled`, i.e. checked unless the card is inactive) — the
  #   edition-metadata screen starts every box unchecked so nothing applies
  #   by accident.
  class ComparisonCardComponent < ApplicationComponent
    Card = Struct.new(
      :label, :meta, :proposed, :cover, :cover_url, :cover_selectable, :show_empty_cover,
      :fields, :identifiers, :info_note, :select_name, :select_value, :selected,
      :input_scope, :fields_disabled, :field_value_prefix, :fields_start_checked,
      keyword_init: true
    )
    FieldRow = Struct.new(:name, :value, :chip, :selectable, keyword_init: true)

    def initialize(card:)
      @card = card
    end

    private

    def field_id(name) = "#{@card.input_scope}field_#{name}"

    def checkbox_name = @card.field_value_prefix ? "field_picks[]" : "fields[]"
    def checkbox_value(name) = @card.field_value_prefix ? "#{@card.field_value_prefix}:#{name}" : name

    def field_checked
      return @card.fields_start_checked unless @card.fields_start_checked.nil?

      !@card.fields_disabled
    end

    # `cover` is a `has_one_attached` proxy (Edition / EnrichmentRecord
    # cover_image) or a single `ActiveStorage::Attachment` picked out of a
    # `has_many_attached` (PendingDecision#candidate_cover) — normalise the
    # "is there an image" check and the thumbnail variant across both.
    def cover_present?
      cover = @card.cover
      cover.respond_to?(:attached?) ? cover.attached? : cover.present?
    end

    def cover_thumb = @card.cover.variant(resize_to_limit: [ 108, 162 ])
  end
end

module Enrichment
  # The on-demand "reconcile this edition against its known sources" screen
  # — the cog on Ui::EditionCardComponent, and the quick right-click cover
  # swap. Unlike PendingDecision#comparison_cards (raised for one named
  # source's proposal, other providers shown for reference only), this is
  # always available and every source's fields are pickable — the reviewer
  # can take the cover from ISFDB, keep the publisher as catalogued, and so
  # on, mixed freely per field. See docs/DESIGN_SYSTEM.md "Edition card"
  # and the comparison-card component's field_value_prefix.
  class EditionMetadataCards
    Card = Ui::ComparisonCardComponent::Card
    FieldRow = Ui::ComparisonCardComponent::FieldRow
    FIELD_ORDER = PendingDecision::EDITION_FIELD_ORDER
    ID_TYPE_LABELS = PendingDecision::ID_TYPE_LABELS

    def self.build(edition) = new(edition).build

    def initialize(edition)
      @edition = edition
    end

    def build
      { edition: current_card, sources: @edition.enrichment_records.order(:provider).map { |r| source_card(r) } }
    end

    private

    def current_card
      fields = FIELD_ORDER.map do |field|
        FieldRow.new(name: field, value: format_field(field, @edition.public_send(field)), chip: @edition.field_sources[field])
      end
      identifiers = EditionIdentifier.for_display(@edition.edition_identifiers).map { |i| [ ID_TYPE_LABELS.fetch(i.id_type, i.id_type.upcase), i.value ] }

      Card.new(label: "Edition · in catalog", cover: @edition.cover_image, cover_chip: @edition.field_sources["cover_image"],
               show_empty_cover: true, fields: fields, identifiers: identifiers)
    end

    # Every field this source knows is pickable — not gated to "the one
    # field that raised a conflict" the way PendingDecision's provider_card
    # is. Nothing pre-checked: an edition already looks how the reviewer
    # wants it most of the time, so applying anything should be deliberate.
    def source_card(record)
      fields = FIELD_ORDER.select { |f| record.fields.key?(f) }.map do |f|
        FieldRow.new(name: f, value: format_field(f, record.fields[f]), selectable: true)
      end

      Card.new(
        label: "#{record.provider.humanize} · on file", meta: record.fetched_at,
        cover: record.cover_image, cover_selectable: record.cover_image.attached?,
        fields: fields, input_scope: "#{record.provider}_",
        field_value_prefix: record.provider, fields_start_checked: false
      )
    end

    def format_field(field, value)
      %w[format format_detail].include?(field) ? value&.humanize : value
    end
  end
end

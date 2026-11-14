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
      { edition: current_card, sources: @edition.enrichment_records.order(:provider).map { |r| source_card(r) } +
                                        self.class.other_printings(@edition).map { |p| printing_card(p) } }
    end

    # The book's other known printings sharing this edition's ISBN — any
    # provider's — that aren't already one of its sources. Publishers reuse
    # an ISBN across reprints (Penguin's Utopia: two Open Library records,
    # three ISFDB printings), so none is this copy for certain, but one may
    # have its cover (ISFDB had no scan with the black title bar; Open
    # Library did). Picking from one doesn't move the edition's anchor.
    def self.other_printings(edition)
      isbns = edition.edition_identifiers.select { |i| %w[isbn13 isbn10].include?(i.id_type) }
                     .filter_map { |i| i.id_type == "isbn10" ? Isbn.to_13(i.value) : i.value }
      return [] if isbns.empty?

      # Its sources, and the printing it's anchored to (an `isfdb` or
      # `openlibrary` identifier) even before that has a source record.
      sources = (edition.enrichment_records.map { |r| [ r.provider, r.external_id.to_s ] } +
                 edition.edition_identifiers.select { |i| %w[isfdb openlibrary].include?(i.id_type) }.map { |i| [ i.id_type, i.value ] }).to_set
      ProviderEdition.where(work_id: edition.works.select(:id), isbn13: isbns).order(:provider, :publish_date)
                     .reject { |p| sources.include?([ p.provider, p.provider_id.to_s ]) }.uniq { |p| [ p.provider, p.provider_id ] }
    end

    def self.printing_fields(printing)
      AddBook::Create.fields(AddBook::EditionCards.from_provider_editions([ printing ]).first)
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

    def printing_card(printing)
      values = self.class.printing_fields(printing)
      fields = FIELD_ORDER.select { |f| values[f.to_sym].present? }.map do |f|
        FieldRow.new(name: f, value: format_field(f, values[f.to_sym]), selectable: true)
      end
      Card.new(
        label: "#{ApplicationHelper::SOURCE_LABELS.fetch(printing.provider, printing.provider.humanize)} · same ISBN, another printing",
        cover_url: printing.cover_url.presence, cover_selectable: printing.cover_url.present?,
        fields: fields, input_scope: "printing#{printing.id}_", field_value_prefix: "printing-#{printing.id}", fields_start_checked: false,
        info_note: [ printing.publisher, printing.publish_date ].compact.join(" · ")
      )
    end

    def format_field(field, value)
      %w[format format_detail].include?(field) ? value&.humanize : value
    end
  end
end

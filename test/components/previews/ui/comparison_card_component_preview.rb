module Ui
  class ComparisonCardComponentPreview < ViewComponent::Preview
    PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    def edition_card
      edition = Edition.create!(publisher: "Orbit", publish_date: "2001", language: "eng", page_count: 502, field_sources: { "publisher" => "goodreads" })
      edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "cover.png", content_type: "image/png")

      card = PendingDecision::Card.new(
        label: "Edition · in catalog", cover: edition.cover_image, show_empty_cover: true,
        fields: [
          PendingDecision::FieldRow.new(name: "publisher", value: "Orbit", chip: "goodreads"),
          PendingDecision::FieldRow.new(name: "publish_date", value: "2001", chip: "goodreads"),
          PendingDecision::FieldRow.new(name: "language", value: "eng", chip: "isfdb")
        ],
        identifiers: [ [ "ISBN-13", "9781841490786" ], [ "ISFDB", "322687" ] ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    def reference_card
      card = PendingDecision::Card.new(
        label: "Goodreads · on file", meta: 1.day.ago, info_note: "Reference only — not part of this decision.",
        fields: [
          PendingDecision::FieldRow.new(name: "publisher", value: "Orbit"),
          PendingDecision::FieldRow.new(name: "format_detail", value: nil)
        ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    def proposed_card
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "proposed.png", content_type: "image/png")

      card = PendingDecision::Card.new(
        label: "ISFDB · proposed", meta: 1.day.ago, proposed: true,
        cover: edition.cover_image, cover_selectable: true,
        fields: [
          PendingDecision::FieldRow.new(name: "publisher", value: "Orbit / Little, Brown UK", selectable: true),
          PendingDecision::FieldRow.new(name: "publish_date", value: "2005", selectable: true),
          PendingDecision::FieldRow.new(name: "language", value: "eng", selectable: false)
        ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    # edition_reconciliation: the incoming Goodreads row — a remote cover URL,
    # no attachment, flagged `proposed`.
    def incoming_feed_card
      card = Ui::ComparisonCardComponent::Card.new(
        label: "Goodreads · incoming", proposed: true,
        cover_url: "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1287032152l/1343099.jpg",
        fields: [
          Ui::ComparisonCardComponent::FieldRow.new(name: "goodreads id", value: "1343099"),
          Ui::ComparisonCardComponent::FieldRow.new(name: "isbn", value: "0812501810"),
          Ui::ComparisonCardComponent::FieldRow.new(name: "read", value: "2024-06-01")
        ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    # edition_reconciliation: one owned edition, pickable — the header is a
    # radio, a checked card takes the conflict ring.
    def selectable_edition_card
      card = Ui::ComparisonCardComponent::Card.new(
        label: "Edition · owned · read", show_empty_cover: true,
        select_name: "target_edition_id", select_value: "42", selected: true,
        fields: [
          Ui::ComparisonCardComponent::FieldRow.new(name: "format", value: "Paperback"),
          Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "Grafton")
        ],
        identifiers: [ [ "ISBN-13", "9780586213872" ], [ "Goodreads", "1343099" ] ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    # enrichment_printing_choice: one ISFDB printing candidate — radio in
    # the header AND per-field checkboxes, its downloaded cover shown as an
    # <img> with an "Apply this cover" box. `fields_disabled` dims the
    # unpicked printings.
    def printing_choice_candidate
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "triad.png", content_type: "image/png")
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · 1986 · Triad Grafton",
        cover: edition.cover_image, cover_selectable: true,
        select_name: "pub_id", select_value: "35246", selected: true,
        input_scope: "pub35246_", fields_disabled: false,
        fields: [
          Ui::ComparisonCardComponent::FieldRow.new(name: "format_detail", value: "Mass market", selectable: true),
          Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "Triad Grafton", selectable: true),
          Ui::ComparisonCardComponent::FieldRow.new(name: "publish_date", value: "1986-05", selectable: true),
          Ui::ComparisonCardComponent::FieldRow.new(name: "page_count", value: 464, selectable: true)
        ]
      )
      render(ComparisonCardComponent.new(card: card))
    end

    def printing_choice_candidate_unpicked
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · 1993 · HarperCollins (UK)",
        select_name: "pub_id", select_value: "35244", selected: false,
        input_scope: "pub35244_", fields_disabled: true,
        fields: [
          Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "HarperCollins (UK)", selectable: true),
          Ui::ComparisonCardComponent::FieldRow.new(name: "publish_date", value: "1993-10", selectable: true)
        ]
      )
      render(ComparisonCardComponent.new(card: card))
    end
  end
end

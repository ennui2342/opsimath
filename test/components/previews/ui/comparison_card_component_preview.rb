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
  end
end

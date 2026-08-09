require "test_helper"

module Ui
  class ComparisonCardComponentTest < ViewComponent::TestCase
    test "renders the label, meta, and each field with its value" do
      card = PendingDecision::Card.new(
        label: "ISFDB · proposed", meta: Time.zone.parse("2026-08-07"), proposed: true,
        fields: [
          PendingDecision::FieldRow.new(name: "publisher", value: "HarperVoyager", selectable: true),
          PendingDecision::FieldRow.new(name: "language", value: "eng", selectable: false)
        ]
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "ISFDB · proposed"
      assert_text "2026-08-07"
      assert_text "HarperVoyager"
      assert_text "eng"
    end

    test "shows (blank) rather than an empty value" do
      card = PendingDecision::Card.new(label: "Edition · in catalog", fields: [
        PendingDecision::FieldRow.new(name: "publisher", value: nil, selectable: false)
      ])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "(blank)"
    end

    test "renders a checked fields[] checkbox only on selectable rows" do
      card = PendingDecision::Card.new(label: "ISFDB · proposed", fields: [
        PendingDecision::FieldRow.new(name: "publisher", value: "HarperVoyager", selectable: true),
        PendingDecision::FieldRow.new(name: "language", value: "eng", selectable: false)
      ])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox][name='fields[]'][value=publisher][checked]"
      assert_selector "input[type=checkbox]", count: 1
    end

    test "renders a field's provenance chip when present" do
      card = PendingDecision::Card.new(label: "Edition · in catalog", fields: [
        PendingDecision::FieldRow.new(name: "publisher", value: "HarperVoyager", chip: "isfdb", selectable: false)
      ])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "isfdb"
    end

    test "renders identifiers when present" do
      card = PendingDecision::Card.new(label: "Edition · in catalog", fields: [], identifiers: [ [ "ISBN-13", "9781841490786" ] ])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "ISBN-13"
      assert_text "9781841490786"
    end

    test "renders an info note when present, with no checkboxes" do
      card = PendingDecision::Card.new(label: "Goodreads · on file", info_note: "Reference only — not part of this decision.", fields: [
        PendingDecision::FieldRow.new(name: "publisher", value: "Orbit", selectable: false)
      ])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "Reference only"
      assert_no_selector "input[type=checkbox]"
    end

    test "renders the attached cover as an image" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("bytes"), filename: "cover.jpg", content_type: "image/jpeg")
      card = PendingDecision::Card.new(label: "Edition · in catalog", cover: edition.cover_image, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "img"
    end

    test "renders a placeholder instead of an image when show_empty_cover is true and nothing is attached" do
      edition = Edition.create!
      card = PendingDecision::Card.new(label: "Edition · in catalog", cover: edition.cover_image, show_empty_cover: true, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_no_selector "img"
      assert_text "No cover"
    end

    test "renders no cover strip at all when show_empty_cover is false and nothing is attached" do
      edition = Edition.create!
      card = PendingDecision::Card.new(label: "Goodreads · on file", cover: edition.cover_image, show_empty_cover: false, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_no_selector "img"
      assert_no_text "No cover"
    end

    test "a selectable cover renders a checked 'Apply this cover' checkbox" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("bytes"), filename: "cover.jpg", content_type: "image/jpeg")
      card = PendingDecision::Card.new(label: "ISFDB · proposed", proposed: true, cover: edition.cover_image, cover_selectable: true, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox][name='fields[]'][value=cover_image][checked]"
      assert_text "Apply this cover"
    end
  end
end

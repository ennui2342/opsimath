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

    test "renders the cover's provenance chip when present" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("bytes"), filename: "cover.jpg", content_type: "image/jpeg")
      card = PendingDecision::Card.new(label: "Edition · in catalog", cover: edition.cover_image, cover_chip: "isfdb", fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_text "isfdb"
    end

    test "renders no cover chip when nothing is attached, even if cover_chip is set" do
      edition = Edition.create!
      card = PendingDecision::Card.new(label: "Edition · in catalog", cover: edition.cover_image, cover_chip: "isfdb", show_empty_cover: true, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_no_text "isfdb"
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

    test "renders a remote cover_url as an image when no attachment is present" do
      card = Ui::ComparisonCardComponent::Card.new(
        label: "Goodreads · incoming", cover_url: "https://example.com/cover.jpg", fields: []
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "img[src='https://example.com/cover.jpg']"
    end

    test "a select_name card puts a radio in the header and takes the conflict ring when checked" do
      card = Ui::ComparisonCardComponent::Card.new(
        label: "Edition · owned", fields: [],
        select_name: "target_edition_id", select_value: "42", selected: true
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "label input[type=radio][name='target_edition_id'][value='42'][checked]"
      assert_selector "div.has-\\[\\:checked\\]\\:ring-1"
    end

    test "input_scope namespaces the checkbox ids so sibling cards don't collide" do
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · 1986", input_scope: "pub35246_", select_name: "pub_id", select_value: "35246", selected: true,
        fields: [ Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "Triad Grafton", selectable: true) ]
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox][name='fields[]'][value=publisher]#pub35246_field_publisher"
      assert_selector "input[type=radio][name='pub_id'][value='35246']#pub35246_select_35246"
    end

    test "fields_disabled renders the card's checkboxes (fields and cover) unchecked and disabled" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("bytes"), filename: "c.png", content_type: "image/png")
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · 1993", input_scope: "pub1_", fields_disabled: true,
        cover: edition.cover_image, cover_selectable: true,
        fields: [ Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "HarperCollins", selectable: true) ]
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox][value=publisher][disabled]"
      assert_no_selector "input[type=checkbox][value=publisher][checked]"
      assert_selector "input[type=checkbox][value=cover_image][disabled]"
    end

    test "cover works from a single has_many_attached ActiveStorage::Attachment, not just a has_one proxy" do
      pd = PendingDecision.create!(kind: "enrichment_printing_choice", payload: {})
      pd.candidate_covers.attach(io: StringIO.new("bytes"), filename: "35246.jpg", content_type: "image/png")
      card = Ui::ComparisonCardComponent::Card.new(label: "ISFDB · 1986", cover: pd.candidate_cover("35246"), cover_selectable: true, fields: [])

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "img"
      assert_selector "input[type=checkbox][value=cover_image]"
    end

    test "field_value_prefix makes checkboxes self-describing as 'provider:field', field_picks[] instead of fields[]" do
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · on file", field_value_prefix: "isfdb", cover: nil,
        fields: [ Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "Orbit", selectable: true) ]
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox][name='field_picks[]'][value='isfdb:publisher']"
      assert_no_selector "input[type=checkbox][name='fields[]']"
    end

    test "fields_start_checked: false starts every box unchecked (and not disabled)" do
      card = Ui::ComparisonCardComponent::Card.new(
        label: "ISFDB · on file", field_value_prefix: "isfdb", fields_start_checked: false,
        fields: [ Ui::ComparisonCardComponent::FieldRow.new(name: "publisher", value: "Orbit", selectable: true) ]
      )

      render_inline(ComparisonCardComponent.new(card: card))

      assert_selector "input[type=checkbox]:not([checked]):not([disabled])"
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

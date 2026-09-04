require "test_helper"

class PendingDecisionTest < ActiveSupport::TestCase
  test "field_candidates returns the latest value per provider that has one for this field" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: 1.day.ago, raw_payload: {}, fields: { "publisher" => "Ace Books" })
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "2", fetched_at: 1.hour.ago, raw_payload: {}, fields: { "publisher" => "Ace" })
    pending = PendingDecision.create!(kind: "enrichment_conflict", payload: { "entity_type" => "Edition", "entity_id" => edition.id })

    candidates = pending.field_candidates(:publisher)

    assert_equal [ "goodreads", "isfdb" ], candidates.map { |c| c[:provider] }.sort
    assert_equal "Ace Books", candidates.find { |c| c[:provider] == "goodreads" }[:value]
    assert_equal "Ace", candidates.find { |c| c[:provider] == "isfdb" }[:value]
  end

  test "field_candidates omits a provider with no value at all for this field" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
    pending = PendingDecision.create!(kind: "enrichment_conflict", payload: { "entity_type" => "Edition", "entity_id" => edition.id })

    assert_equal [], pending.field_candidates(:publisher)
  end

  test "field_candidates is empty when the decision's entity can't be resolved" do
    pending = PendingDecision.create!(kind: "possible_duplicate_work", payload: { "goodreads_book_id" => "1" })

    assert_equal [], pending.field_candidates(:publisher)
  end

  test "field_diffs is empty for a kind whose payload carries no field-level data" do
    pending = PendingDecision.create!(kind: "possible_duplicate_work", payload: { "goodreads_book_id" => "1" })

    assert_equal [], pending.field_diffs
  end

  test "field_diffs derives current/proposed live from the entity column and the named source's latest EnrichmentRecord" do
    edition = Edition.create!(publisher: "St Martins Pr")
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: { "publisher" => "HarperVoyager" })
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    diff = pending.field_diffs.sole
    assert_equal "publisher", diff[:field]
    assert_equal "St Martins Pr", diff[:current]
    assert_equal "HarperVoyager", diff[:proposed]
    assert_equal "isfdb", diff[:source]
  end

  test "field_diffs reflects the entity's current column value even if it changed after the decision was raised — not a frozen snapshot" do
    edition = Edition.create!(publisher: "St Martins Pr")
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: { "publisher" => "HarperVoyager" })
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    edition.update!(publisher: "A Manually Corrected Name")

    assert_equal "A Manually Corrected Name", pending.field_diffs.sole[:current]
  end

  test "field_diffs special-cases cover_image with no EnrichmentRecord lookup — it's an attachment, not a column" do
    edition = Edition.create!
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "cover_image" ], "source" => "isfdb" }
    )

    diff = pending.field_diffs.sole
    assert_equal "cover_image", diff[:field]
    assert_nil diff[:current]
    assert_nil diff[:proposed]
  end

  test "field_diffs raises rather than silently returning nothing when the named source has no backing EnrichmentRecord" do
    edition = Edition.create!(publisher: "St Martins Pr")
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    assert_raises(RuntimeError) { pending.field_diffs }
  end

  test "comparison_cards builds an edition card, a card per other provider, and the proposing card" do
    edition = Edition.create!(publisher: "Orbit", publish_date: "2001", language: "eng", page_count: 502, field_sources: { "publisher" => "goodreads" })
    edition.cover_image.attach(io: StringIO.new("current-bytes"), filename: "current.jpg", content_type: "image/jpeg")
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: 1.day.ago, raw_payload: {}, fields: { "publisher" => "Orbit", "format_detail" => nil })
    isfdb = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "2", fetched_at: 1.hour.ago, raw_payload: {}, fields: { "publisher" => "Orbit / Little, Brown UK", "publish_date" => "2005", "language" => "eng" })
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "publisher", "publish_date" ] }
    )

    cards = pending.comparison_cards

    assert_equal "Edition · in catalog", cards[:edition].label
    assert_equal "Orbit", cards[:edition].fields.find { |f| f.name == "publisher" }.value
    assert_equal "goodreads", cards[:edition].fields.find { |f| f.name == "publisher" }.chip
    assert_equal edition.cover_image.blob, cards[:edition].cover.blob

    other = cards[:others].sole
    assert_equal "Goodreads · on file", other.label
    assert_equal "Orbit", other.fields.find { |f| f.name == "publisher" }.value
    assert_nil other.fields.find { |f| f.name == "format_detail" }.value
    assert_not other.fields.any? { |f| f.selectable }

    proposed = cards[:proposed]
    assert_equal "Isfdb · proposed", proposed.label
    publisher_row = proposed.fields.find { |f| f.name == "publisher" }
    assert publisher_row.selectable
    assert_equal "Orbit / Little, Brown UK", publisher_row.value
    language_row = proposed.fields.find { |f| f.name == "language" }
    assert_not language_row.selectable
  end

  test "comparison_cards' proposed card offers the cover checkbox when the source has one and it's in payload fields" do
    edition = Edition.create!
    record = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
    record.cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "cover_image" ] }
    )

    proposed = pending.comparison_cards[:proposed]

    assert proposed.cover_selectable
    assert_equal "new-bytes", proposed.cover.download
  end

  test "comparison_cards is nil when the entity isn't an Edition" do
    pending = PendingDecision.create!(kind: "possible_duplicate_work", payload: { "goodreads_book_id" => "1" })

    assert_nil pending.comparison_cards
  end

  test "comparison_cards is nil when the named source has no backing EnrichmentRecord" do
    edition = Edition.create!(publisher: "St Martins Pr")
    pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    assert_nil pending.comparison_cards
  end

  test "printing_choice_cards: a reference card plus one selectable card per ISFDB printing, first pre-picked" do
    edition = Edition.create!(publisher: "Existing")
    pending = PendingDecision.create!(kind: "enrichment_printing_choice", payload: {
      "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "isbn" => "0586065504",
      "candidates" => [
        { "_isfdb_pub_id" => 35244, "publisher" => "HarperCollins (UK)", "publish_date" => "1993-10", "binding" => "pb", "page_count" => 464, "cover_artists" => [ "Richard Clifton-Dey" ] },
        { "_isfdb_pub_id" => 35246, "publisher" => "Triad Grafton", "publish_date" => "1986-05", "binding" => "pb", "page_count" => 464 }
      ]
    })
    pending.candidate_covers.attach(io: StringIO.new("cover-a"), filename: "35244.jpg", content_type: "image/jpeg")

    cards = pending.printing_choice_cards

    assert_equal "Edition · in catalog", cards[:edition].label
    assert_nil cards[:edition].select_name # reference only

    first, second = cards[:candidates]
    assert_equal "ISFDB · 1993 · HarperCollins (UK)", first.label
    assert_equal "pub_id", first.select_name
    assert_equal "35244", first.select_value
    assert first.selected
    assert_not first.fields_disabled
    assert_equal "pub35244_", first.input_scope
    assert(first.fields.all?(&:selectable))
    assert_equal "Mass market", first.fields.find { |f| f.name == "format_detail" }.value
    assert first.cover_selectable # its downloaded cover renders as an <img> + checkbox
    assert_equal "35244.jpg", first.cover.filename.to_s
    assert_equal "Richard Clifton-Dey", first.fields.find { |f| f.name == "cover_artist" }.value

    assert_not second.selected
    assert second.fields_disabled
    assert_not second.cover_selectable # no cover downloaded for this printing
  end

  test "printing_choice_cards is nil for other kinds" do
    assert_nil PendingDecision.new(kind: "enrichment_conflict").printing_choice_cards
  end

  test "display_title uses the Edition's work titles, or the payload title, or a placeholder" do
    work = Work.create!(title: "Marrow", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work:, edition:)
    on_edition = PendingDecision.create!(kind: "enrichment_conflict", payload: {
      "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb"
    })
    assert_equal "Marrow", on_edition.display_title

    from_payload = PendingDecision.new(kind: "reread_conflict", payload: { "title" => "Downbelow Station" })
    assert_equal "Downbelow Station", from_payload.display_title

    assert_equal "Untitled reread_conflict", PendingDecision.new(kind: "reread_conflict", payload: {}).display_title
  end
end

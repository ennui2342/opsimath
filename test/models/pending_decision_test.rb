require "test_helper"

class PendingDecisionTest < ActiveSupport::TestCase
  test "field_candidates returns the latest value per provider that has one for this field" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: 1.day.ago, raw_payload: {}, fields: { "publisher" => "Ace Books" })
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "2", fetched_at: 1.hour.ago, raw_payload: {}, fields: { "publisher" => "Ace" })
    pending = PendingDecision.create!(kind: "enrichment_field_conflict", payload: { "entity_type" => "Edition", "entity_id" => edition.id })

    candidates = pending.field_candidates(:publisher)

    assert_equal [ "goodreads", "isfdb" ], candidates.map { |c| c[:provider] }.sort
    assert_equal "Ace Books", candidates.find { |c| c[:provider] == "goodreads" }[:value]
    assert_equal "Ace", candidates.find { |c| c[:provider] == "isfdb" }[:value]
  end

  test "field_candidates only surfaces the latest EnrichmentRecord per provider, not every historical fetch" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: 2.days.ago, raw_payload: {}, fields: { "publisher" => "Old Name" })
    EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: 1.hour.ago, raw_payload: {}, fields: { "publisher" => "New Name" })
    pending = PendingDecision.create!(kind: "enrichment_field_conflict", payload: { "entity_type" => "Edition", "entity_id" => edition.id })

    candidates = pending.field_candidates(:publisher)

    assert_equal [ { provider: "isfdb", value: "New Name" } ], candidates.map { |c| c.slice(:provider, :value) }
  end

  test "field_candidates omits a provider with no value at all for this field" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
    pending = PendingDecision.create!(kind: "enrichment_field_conflict", payload: { "entity_type" => "Edition", "entity_id" => edition.id })

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
      kind: "enrichment_field_conflict",
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
      kind: "enrichment_field_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    edition.update!(publisher: "A Manually Corrected Name")

    assert_equal "A Manually Corrected Name", pending.field_diffs.sole[:current]
  end

  test "field_diffs special-cases cover_image with no EnrichmentRecord lookup — it's an attachment, not a column" do
    edition = Edition.create!
    pending = PendingDecision.create!(
      kind: "enrichment_edition_mismatch",
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
      kind: "enrichment_field_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    assert_raises(RuntimeError) { pending.field_diffs }
  end
end

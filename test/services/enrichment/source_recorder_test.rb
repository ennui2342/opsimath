require "test_helper"

module Enrichment
  class SourceRecorderTest < ActiveSupport::TestCase
    test "records an EnrichmentRecord and fills every blank field, tagging field_sources" do
      edition = Edition.create!

      SourceRecorder.record(
        entity: edition, provider: "goodreads", external_id: "12345", raw_payload: { "Publisher" => "Ace Books" },
        fields: { publisher: "Ace Books", format: "paperback" }
      )

      edition.reload
      assert_equal "Ace Books", edition.publisher
      assert_equal "paperback", edition.format
      assert_equal "goodreads", edition.field_sources["publisher"]
      assert_equal "goodreads", edition.field_sources["format"]

      record = EnrichmentRecord.find_by!(entity: edition, provider: "goodreads", external_id: "12345")
      assert_equal({ "Publisher" => "Ace Books" }, record.raw_payload)
      assert_equal({ "publisher" => "Ace Books", "format" => "paperback" }, record.fields)
    end

    test "an empty fields hash still creates the EnrichmentRecord but writes nothing to the entity" do
      edition = Edition.create!

      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "999", raw_payload: { "title" => "A Book" })

      assert_equal({}, edition.reload.field_sources)
      record = EnrichmentRecord.find_by!(entity: edition, provider: "goodreads", external_id: "999")
      assert_equal({}, record.fields)
    end

    test "the EnrichmentRecord's fields column captures what was proposed even when a field ends up in conflict" do
      edition = Edition.create!(publisher: "Berkley Windhover")

      SourceRecorder.record(
        entity: edition, provider: "isfdb", external_id: "42", raw_payload: {},
        fields: { publisher: "Ace Books" }
      )

      assert_equal "Berkley Windhover", edition.reload.publisher # untouched — a real conflict, not silently overwritten
      record = EnrichmentRecord.find_by!(entity: edition, provider: "isfdb", external_id: "42")
      assert_equal({ "publisher" => "Ace Books" }, record.fields) # still recorded regardless of the fill/conflict outcome
      assert_equal 1, PendingDecision.count
    end

    test "a genuine conflict creates a bundled enrichment_conflict decision — same kind, same mechanism, regardless of source" do
      edition = Edition.create!(publisher: "Berkley Windhover")

      SourceRecorder.record(entity: edition, provider: "isfdb", external_id: "42", raw_payload: {}, fields: { publisher: "Ace Books" })

      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal "Edition", decision.payload["entity_type"]
      assert_equal edition.id, decision.payload["entity_id"]
      assert_equal [ "publisher" ], decision.payload["fields"]
      assert_equal "isfdb", decision.payload["source"]
      assert_nil edition.reload.field_sources["publisher"] # never set — no value was ever applied
    end

    test "re-flagging the same conflict from the same source reuses the existing pending decision" do
      edition = Edition.create!(publisher: "Berkley Windhover")

      SourceRecorder.record(entity: edition, provider: "isfdb", external_id: "1", raw_payload: {}, fields: { publisher: "Ace Books" })
      SourceRecorder.record(entity: edition, provider: "isfdb", external_id: "2", raw_payload: {}, fields: { publisher: "Ace Books" })

      assert_equal 1, PendingDecision.where(kind: "enrichment_conflict").count
    end

    test "a conflict from a different source never reuses another source's pending decision" do
      edition = Edition.create!(publisher: "Berkley Windhover")

      SourceRecorder.record(entity: edition, provider: "isfdb", external_id: "1", raw_payload: {}, fields: { publisher: "Ace Books" })
      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "2", raw_payload: {}, fields: { publisher: "Harper" })

      assert_equal 2, PendingDecision.where(kind: "enrichment_conflict").count
    end

    test "a cover conflict bundles into the same enrichment_conflict decision as any other field — proves Goodreads and ISFDB now share one mechanism" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")

      SourceRecorder.record(
        entity: edition, provider: "goodreads", external_id: "1", raw_payload: {},
        fields: { cover_image: "https://i.gr-assets.com/images/cover.jpg" }
      )

      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal [ "cover_image" ], decision.payload["fields"]
      assert_equal "goodreads", decision.payload["source"]
      assert_equal "isfdb-bytes", edition.reload.cover_image.download # untouched pending review
    end

    test "multiple simultaneous fields (including cover) from a non-ISFDB source bundle together too, not just ISFDB" do
      edition = Edition.create!(publisher: "Berkley Windhover")
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")

      SourceRecorder.record(
        entity: edition, provider: "goodreads", external_id: "1", raw_payload: {},
        fields: { publisher: "Ace Books", cover_image: "https://i.gr-assets.com/images/cover.jpg" }
      )

      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal %w[publisher cover_image], decision.payload["fields"]
    end

    test "a second fetch from the same provider updates the same EnrichmentRecord in place, not a second row" do
      edition = Edition.create!

      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "1", raw_payload: { "a" => 1 }, fields: { publisher: "Ace Books" })
      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "1", raw_payload: { "a" => 2 }, fields: { format: "paperback" })

      assert_equal 1, EnrichmentRecord.where(entity: edition, provider: "goodreads").count
    end

    test "a second fetch from the same provider merges additively — a field not repeated stays as recorded" do
      edition = Edition.create!

      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "1", raw_payload: {}, fields: { publisher: "Ace Books" })
      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "1", raw_payload: {}, fields: { format: "paperback" })

      record = EnrichmentRecord.find_by!(entity: edition, provider: "goodreads")
      assert_equal({ "publisher" => "Ace Books", "format" => "paperback" }, record.fields)
    end

    test "a second fetch from the same provider overwrites a field it repeats, and re-integrates it against the entity" do
      # Mark, 2026-08-09: one provider updating its own earlier belief
      # isn't a conflict at the EnrichmentRecord layer — it's just a
      # newer fact from the same source. But it IS new information as
      # far as the entity is concerned, so it goes through the standard
      # fill/conflict workflow again, same as any other field this fetch
      # names.
      edition = Edition.create!(publisher: "Old Publisher", field_sources: { "publisher" => "goodreads" })

      SourceRecorder.record(entity: edition, provider: "goodreads", external_id: "1", raw_payload: {}, fields: { publisher: "New Publisher" })

      record = EnrichmentRecord.find_by!(entity: edition, provider: "goodreads")
      assert_equal "New Publisher", record.fields["publisher"]
      # The Edition already had a value from a different source lineage
      # (simulated here — field_sources says "goodreads" but the value
      # itself predates this fetch), so this is a genuine fill/conflict
      # decision, not an automatic overwrite of the Edition column.
      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal [ "publisher" ], decision.payload["fields"]
      assert_equal "Old Publisher", edition.reload.publisher # untouched — held for review, same as any other conflict
    end

    test "integrate bundles a mix of custom-planned fields (e.g. ISFDB's own refinement logic) exactly the same way" do
      edition = Edition.create!(publisher: "Berkley Windhover", format: "paperback")
      custom_plan = FieldApplier::Plan.new(record: edition, field: :format, action: :conflict, value: "hardcover", source: "isfdb", current: "paperback")
      generic_plan = FieldApplier.plan(edition, :publish_date, "2010", "isfdb")

      SourceRecorder.integrate([ custom_plan, generic_plan ], entity: edition, provider: "isfdb")

      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_equal %w[format publish_date], decision.payload["fields"]
      assert_nil edition.reload.publish_date # held back alongside the conflict, even though it was a clean fill
    end
  end
end

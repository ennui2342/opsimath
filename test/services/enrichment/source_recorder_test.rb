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
  end
end

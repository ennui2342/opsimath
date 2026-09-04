require "test_helper"

module Enrichment
  class EditionMetadataCardsTest < ActiveSupport::TestCase
    test "a reference card for the edition, plus one selectable card per known source" do
      edition = Edition.create!(publisher: "Ace Books", format: "paperback", field_sources: { "cover_image" => "isfdb" })
      edition.cover_image.attach(io: StringIO.new("bytes"), filename: "c.jpg", content_type: "image/jpeg")
      EnrichmentRecord.create!(
        entity: edition, provider: "goodreads", external_id: "1", fetched_at: 1.day.ago,
        raw_payload: {}, fields: { "publisher" => "Ace" }
      )
      EnrichmentRecord.create!(
        entity: edition, provider: "isfdb", external_id: "2", fetched_at: 1.hour.ago,
        raw_payload: {}, fields: { "publisher" => "Ace Books", "language" => "eng", "cover_artist" => "John Schoenherr" }
      )

      cards = EditionMetadataCards.build(edition)

      assert_equal "Edition · in catalog", cards[:edition].label
      assert_equal "Ace Books", cards[:edition].fields.find { |f| f.name == "publisher" }.value
      assert(cards[:edition].fields.none?(&:selectable)) # reference only
      assert_equal "isfdb", cards[:edition].cover_chip

      labels = cards[:sources].map(&:label)
      assert_equal [ "Goodreads · on file", "Isfdb · on file" ], labels

      goodreads = cards[:sources].find { |c| c.label.start_with?("Goodreads") }
      assert(goodreads.fields.all?(&:selectable))
      assert_not goodreads.fields_start_checked # nothing pre-ticked
      assert_equal "goodreads", goodreads.field_value_prefix
      assert_equal "goodreads_", goodreads.input_scope
      assert_equal [ "publisher" ], goodreads.fields.map(&:name) # only fields this source actually has

      isfdb = cards[:sources].find { |c| c.label.start_with?("Isfdb") }
      assert_equal %w[publisher cover_artist language], isfdb.fields.map(&:name)
      assert_equal "John Schoenherr", isfdb.fields.find { |f| f.name == "cover_artist" }.value
    end

    test "a source's fields are limited to what it actually has, and only an attached cover is offered" do
      edition = Edition.create!
      record = EnrichmentRecord.create!(
        entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
        raw_payload: {}, fields: { "publisher" => "Orbit" }
      )

      cards = EditionMetadataCards.build(edition)
      source = cards[:sources].sole

      assert_not source.cover_selectable # no cover_image attached on the record
      record.cover_image.attach(io: StringIO.new("bytes"), filename: "c.jpg", content_type: "image/jpeg")

      cards_with_cover = EditionMetadataCards.build(edition)
      assert cards_with_cover[:sources].sole.cover_selectable
    end

    test "with no enrichment records at all, sources is empty" do
      edition = Edition.create!
      cards = EditionMetadataCards.build(edition)

      assert_empty cards[:sources]
      assert_equal "Edition · in catalog", cards[:edition].label
    end
  end
end

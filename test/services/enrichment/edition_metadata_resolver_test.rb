require "test_helper"

module Enrichment
  class EditionMetadataResolverTest < ActiveSupport::TestCase
    setup do
      @edition = Edition.create!(publisher: "Wrong On File", format: "hardcover")
      @goodreads = EnrichmentRecord.create!(
        entity: @edition, provider: "goodreads", external_id: "1", fetched_at: 1.day.ago,
        raw_payload: {}, fields: { "publisher" => "Orbit (Goodreads)" }
      )
      @isfdb = EnrichmentRecord.create!(
        entity: @edition, provider: "isfdb", external_id: "2", fetched_at: 1.hour.ago,
        raw_payload: {}, fields: { "publisher" => "Orbit", "language" => "eng" }
      )
    end

    test "applies each pick from its named source, mixing sources freely" do
      applied = EditionMetadataResolver.apply(@edition, picks: [ "isfdb:publisher", "isfdb:language" ])

      @edition.reload
      assert_equal %w[publisher language], applied
      assert_equal "Orbit", @edition.publisher
      assert_equal "eng", @edition.language
      assert_equal "isfdb", @edition.field_sources["publisher"]
      assert_equal "isfdb", @edition.field_sources["language"]
    end

    test "picks from different sources for different fields in one call" do
      EditionMetadataResolver.apply(@edition, picks: [ "goodreads:publisher" ])

      assert_equal "Orbit (Goodreads)", @edition.reload.publisher
      assert_equal "goodreads", @edition.field_sources["publisher"]
    end

    test "cover_image pick attaches that source's cover blob" do
      @isfdb.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "c.jpg", content_type: "image/jpeg")

      EditionMetadataResolver.apply(@edition, picks: [ "isfdb:cover_image" ])

      @edition.reload
      assert @edition.cover_image.attached?
      assert_equal "isfdb-bytes", @edition.cover_image.download
      assert_equal "isfdb", @edition.field_sources["cover_image"]
    end

    test "blank/empty picks are a no-op" do
      applied = EditionMetadataResolver.apply(@edition, picks: [ "", nil ])

      assert_empty applied
      assert_equal "Wrong On File", @edition.reload.publisher
    end

    test "raises for an unknown provider" do
      assert_raises(EditionMetadataResolver::InvalidPick) do
        EditionMetadataResolver.apply(@edition, picks: [ "nonexistent:publisher" ])
      end
    end

    test "raises for a field the named source doesn't actually have" do
      assert_raises(EditionMetadataResolver::InvalidPick) do
        EditionMetadataResolver.apply(@edition, picks: [ "goodreads:page_count" ])
      end
    end

    test "raises for a cover pick when the named source has no cover attached" do
      assert_raises(EditionMetadataResolver::InvalidPick) do
        EditionMetadataResolver.apply(@edition, picks: [ "isfdb:cover_image" ])
      end
    end

    test "raises for a malformed pick" do
      assert_raises(EditionMetadataResolver::InvalidPick) { EditionMetadataResolver.apply(@edition, picks: [ "publisher" ]) }
    end
  end
end

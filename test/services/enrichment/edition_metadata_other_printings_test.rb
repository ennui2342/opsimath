require "test_helper"

module Enrichment
  class EditionMetadataOtherPrintingsTest < ActiveSupport::TestCase
    setup do
      @work = Work.create!(title: "Utopia", literary_form: "novel")
      @edition = Edition.create!(publisher: "Penguin Books", publish_date: "1974")
      EditionContent.create!(work: @work, edition: @edition)
      @edition.edition_identifiers.create!(id_type: "isbn13", value: "9780140441659")
      @edition.edition_identifiers.create!(id_type: "isfdb", value: "445208")
      EnrichmentRecord.create!(entity: @edition, provider: "isfdb", external_id: "445208", fetched_at: Time.current, raw_payload: {}, fields: {})
      ProviderEdition.create!(work: @work, provider: "isfdb", provider_id: "445208", isbn13: "9780140441659", publisher: "Penguin Books")
      @ol = ProviderEdition.create!(work: @work, provider: "openlibrary", provider_id: "OL832401M", isbn13: "9780140441659",
                                    publisher: "Penguin Books", publish_date: "1965", page_count: 154, cover_url: "https://covers.test/ol.jpg")
      ProviderEdition.create!(work: @work, provider: "openlibrary", provider_id: "OL999M", isbn13: "9780000000000", publisher: "Other")
    end

    test "the cog offers the book's other printings with this ISBN, not the edition's own source nor other ISBNs" do
      assert_equal [ @ol ], EditionMetadataCards.other_printings(@edition)
      @edition.enrichment_records.delete_all # anchored before its record exists: still not "another printing"
      assert_equal [ @ol ], EditionMetadataCards.other_printings(@edition.reload)
      card = EditionMetadataCards.build(@edition)[:sources].last
      assert_match "same ISBN, another printing", card.label
      assert card.cover_selectable
    end

    test "taking a field and the cover from another printing leaves the edition anchored to ISFDB" do
      stub_request(:get, "https://covers.test/ol.jpg").to_return(status: 200, body: File.binread(file_fixture("cover.png")), headers: { "Content-Type" => "image/png" })

      EditionMetadataResolver.apply(@edition, picks: [ "printing-#{@ol.id}:page_count", "printing-#{@ol.id}:cover_image" ])

      @edition.reload
      assert_equal 154, @edition.page_count
      assert @edition.cover_image.attached?
      assert_equal %w[manual manual], @edition.field_sources.values_at("page_count", "cover_image")
      assert_equal [ "445208" ], @edition.edition_identifiers.where(id_type: "isfdb").pluck(:value)
    end
  end
end

require "test_helper"

class AnchoredRefreshTest < ActiveSupport::TestCase
  setup do
    @work = Work.create!(title: "The Stochastic Man", literary_form: "novel")
    @edition = Edition.create!(publisher: "Hodder and Stoughton", publish_date: "1978", page_count: 189, cover_artist: "Jim Burns",
                               format: "paperback", field_sources: { "publisher" => "goodreads", "publish_date" => "isfdb", "page_count" => "manual" })
    EditionContent.create!(work: @work, edition: @edition)
    @edition.edition_identifiers.create!(id_type: "isbn13", value: "9780340228654")
    @row = @work.provider_editions.create!(provider: "isfdb", provider_id: "42", isbn13: "9780340228654", title: "The Stochastic Man",
                                           publisher: "Coronet Books", publish_date: "1978-05", page_count: 192, binding: "pb",
                                           cover_artist: "Jim Burns", language: "eng")
  end

  def plan = AnchoredRefresh.plan(Edition.where(id: @edition.id).includes(:edition_identifiers, works: :provider_editions)).sole

  def action(p, field) = p.fields.find { |f| f.field == field }.action

  test "anchored by its ISFDB identifier: each field classified against the anchor's record" do
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "42")

    p = plan

    assert_equal :anchored, p.anchor_status
    assert_equal :replace, action(p, :publisher)    # Goodreads' value; ISFDB says Coronet
    assert_equal :update, action(p, :publish_date)  # ISFDB's own value, now more precise
    assert_equal :manual, action(p, :page_count)    # Mark's, kept
    assert_equal :fill, action(p, :language)        # empty here
    assert_equal :same, action(p, :cover_artist)
    assert_equal :fill, action(p, :format_detail)   # pb -> mass market
  end

  test "no identifier: a unique ISBN among the book's printings would anchor it; two make it ambiguous" do
    assert_equal :by_isbn, plan.anchor_status

    @work.provider_editions.create!(provider: "isfdb", provider_id: "43", isbn13: "9780340228654", publisher: "Coronet Books", publish_date: "1981")
    assert_equal :ambiguous, AnchoredRefresh.plan(Edition.where(id: @edition.id).includes(:edition_identifiers, works: :provider_editions)).sole.anchor_status
  end

  test "on Open Library, but ISFDB has its printing: ISFDB becomes the anchor and its values win" do
    ol = @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL9M", isbn13: "9780340228654", publisher: "Hodder")
    @edition.edition_identifiers.create!(id_type: "openlibrary", value: ol.provider_id)
    @edition.update!(cover_artist: nil, field_sources: { "publisher" => "openlibrary" })

    p = plan
    assert_equal [ :by_isbn, "isfdb" ], [ p.anchor_status, p.anchor.provider ]
    assert_equal :fill, action(p, :cover_artist)
    assert_equal :replace, action(p, :publisher)

    @work.provider_editions.create!(provider: "isfdb", provider_id: "43", isbn13: "9780340228654", publisher: "Coronet Books")
    assert_equal [ :anchored, "openlibrary" ], [ plan.anchor_status, plan.anchor.provider ] # two ISFDB printings: stays on Open Library
  end

  test "an edition whose printing is in question is held" do
    PendingDecision.create!(kind: "enrichment_printing_choice", payload: { entity_type: "Edition", entity_id: @edition.id, source: "isfdb", candidates: [] })

    assert_equal :held, plan.anchor_status
  end

  test "another provider's record of the same printing fills what the anchor leaves empty" do
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "42")
    @row.update!(language: nil)
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M", isbn13: "9780340228654", language: "eng")

    assert_equal [ [ :language, "eng", "openlibrary" ] ], plan.secondary.map { |f| [ f.field, f.proposed, f.source ] }
  end

  test "several records of the printing from another provider fill a field when they agree — the cover included" do
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "42")
    @row.update!(language: nil)
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M", isbn13: "9780340228654")
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL2M", isbn13: "9780340228654", language: "eng",
                                    cover_url: "https://covers.openlibrary.org/b/id/908955-L.jpg")

    fills = plan.secondary.to_h { |f| [ f.field, f.proposed ] }
    assert_equal "eng", fills[:language]
    assert_equal "https://covers.openlibrary.org/b/id/908955-L.jpg", fills[:cover_image]

    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL3M", isbn13: "9780340228654", language: "fre")
    assert_nil plan.secondary.find { |f| f.field == :language } # they disagree: left
  end

  test "Open Library as the anchor fills gaps but doesn't overrule what's there" do
    @row.destroy
    ol = @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL9M", isbn13: "9780340228654",
                                         publisher: "Hodder & Stoughton Ltd", publish_date: "1978-05-11", language: "eng")

    p = plan

    assert_equal [ :by_isbn, "openlibrary" ], [ p.anchor_status, p.anchor.provider ]
    assert_equal :keep, action(p, :publisher)
    assert_equal :fill, action(p, :language)
  end

  test "apply: writes with the provider as source, keeps Mark's own, records the anchor, the record and an event" do
    stub_request(:get, %r{https://covers\.test/.*}).to_return(status: 200, body: File.binread(Rails.root.join("test/fixtures/files/cover.png")),
                                                             headers: { "Content-Type" => "image/png" })
    @row.update!(cover_url: "https://covers.test/42.jpg")

    assert_equal 1, AnchoredRefresh.apply(Edition.where(id: @edition.id).includes(:edition_identifiers, works: :provider_editions))
    @edition.reload

    assert_equal [ "Coronet Books", "1978-05", 189, "eng", "mass_market" ],
                 [ @edition.publisher, @edition.publish_date, @edition.page_count, @edition.language, @edition.format_detail ]
    assert_equal [ "isfdb", "manual" ], @edition.field_sources.values_at("publisher", "page_count")
    assert @edition.cover_image.attached?
    assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "42") # anchored by ISBN, now recorded
    assert_equal "https://covers.test/42.jpg", EnrichmentRecord.find_by(entity: @edition, provider: "isfdb").raw_payload["cover_url"]
    assert_match(/The Stochastic Man: .*publisher.* from ISFDB/, CatalogueEvent.last.summary)

    assert_equal 0, AnchoredRefresh.apply(Edition.where(id: @edition.id).includes(:edition_identifiers, works: :provider_editions)) # nothing left
  end

  test "a value chosen with the metadata cog is Mark's: the refresh leaves it" do
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "42")
    EnrichmentRecord.create!(entity: @edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: { "publisher" => "Hodder and Stoughton" })
    Enrichment::EditionMetadataResolver.apply(@edition, picks: [ "goodreads:publisher" ])

    assert_equal :manual, action(plan, :publisher)
  end
end

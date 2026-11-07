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
end

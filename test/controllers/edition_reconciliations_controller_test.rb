require "test_helper"

class EditionReconciliationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @work = Work.create!(title: "Facets", literary_form: "novel")
    WorkContributor.create!(work: @work, contributor: Contributor.create!(name: "Walter Jon Williams"), role: "author")
    @edition = Edition.create!(format: "paperback", publisher: "Grafton")
    EditionContent.create!(work: @work, edition: @edition)
    EditionIdentifier.create!(edition: @edition, id_type: "goodreads", value: "3945054")
    Copy.create!(edition: @edition, disposition: "owned")

    @rec = EditionReconciliation.create!(work: @work, payload: {
      "goodreads_book_id" => "1343099", "shelf" => "read", "work_id" => @work.id,
      "candidate_edition_ids" => [ @edition.id ],
      "feed_item" => { "goodreads_book_id" => "1343099", "title" => "Facets", "author_name" => "Walter Jon Williams",
                       "isbn" => nil, "book_image_url" => nil, "user_read_at" => "2024-06-01" }
    })
  end

  test "redirects to login when not authenticated" do
    get edition_reconciliations_url
    assert_redirected_to new_session_path
  end

  test "index lists pending reconciliations" do
    sign_in_as users(:one)
    get edition_reconciliations_url

    assert_response :success
    assert_select "a", text: /Facets/
  end

  test "show renders the incoming feed row and the work's editions" do
    sign_in_as users(:one)
    get edition_reconciliation_url(@rec)

    assert_response :success
    assert_select "body", /Goodreads · incoming/
    assert_select "body", /1343099/
    assert_select "input[type=radio][name='target_edition_id'][value=?]", @edition.id.to_s
    assert_select "input[type=radio][name='resolution'][value='relink'][checked]"
    assert_select "select[name='source']"
  end

  test "resolve relink applies and advances via turbo stream" do
    sign_in_as users(:one)
    other = EditionReconciliation.create!(work: @work, payload: @rec.payload.merge("goodreads_book_id" => "222"))

    post resolve_edition_reconciliation_url(@rec),
      params: { resolution: "relink", target_edition_id: @edition.id },
      as: :turbo_stream

    assert_response :success
    assert @rec.reload.resolved?
    assert @edition.edition_identifiers.exists?(id_type: "goodreads", value: "1343099")
    assert_match other.work.title, response.body # advanced to the next one
  end

  test "resolve reject via the dedicated button" do
    sign_in_as users(:one)

    post resolve_edition_reconciliation_url(@rec), params: { resolution: "rejected" }, as: :turbo_stream

    assert @rec.reload.resolution_rejected?
  end

  test "an invalid resolution redirects back with an alert" do
    sign_in_as users(:one)

    post resolve_edition_reconciliation_url(@rec), params: { resolution: "relink" } # no target

    assert_redirected_to edition_reconciliation_url(@rec)
    assert @rec.reload.pending?
  end
end

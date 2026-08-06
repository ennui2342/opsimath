require "test_helper"

class PendingDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @edition = Edition.create!(publisher: "St Martins Pr")
    work = Work.create!(title: "The Gold Coast", literary_form: "novel")
    EditionContent.create!(work: work, edition: @edition)
    @pending = PendingDecision.create!(
      kind: "enrichment_field_conflict",
      payload: {
        "entity_type" => "Edition", "entity_id" => @edition.id, "field" => "publisher",
        "current_value" => "St Martins Pr", "proposed" => [ { "value" => "HarperVoyager", "source" => "isfdb" } ]
      }
    )
  end

  test "redirects to login when not authenticated" do
    get pending_decisions_url
    assert_redirected_to new_session_path
  end

  test "index lists pending decisions with a link to the book" do
    sign_in_as users(:one)

    get pending_decisions_url

    assert_response :success
    assert_select "a", text: /The Gold Coast/
  end

  test "show renders the field diff for the entity" do
    sign_in_as users(:one)

    get pending_decision_url(@pending)

    assert_response :success
    assert_select "body", /St Martins Pr/
    assert_select "body", /HarperVoyager/
  end

  test "accept applies the field, resolves the decision, and responds with the next pending decision" do
    sign_in_as users(:one)
    other = PendingDecision.create!(
      kind: "enrichment_field_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "field" => "format", "current_value" => nil, "proposed" => [ { "value" => "hardcover", "source" => "isfdb" } ] }
    )

    post accept_pending_decision_url(@pending), as: :turbo_stream

    assert_response :success
    assert_equal "HarperVoyager", @edition.reload.publisher
    assert_equal "accepted", @pending.reload.status
    assert_match other.id.to_s, response.body
  end

  test "reject leaves the entity untouched and resolves the decision" do
    sign_in_as users(:one)

    post reject_pending_decision_url(@pending), as: :turbo_stream

    assert_response :success
    assert_equal "St Martins Pr", @edition.reload.publisher
    assert_equal "rejected", @pending.reload.status
  end

  test "accepting the last pending decision shows the all-caught-up state" do
    sign_in_as users(:one)

    post accept_pending_decision_url(@pending), as: :turbo_stream

    assert_response :success
    assert_match "All caught up", response.body
  end
end

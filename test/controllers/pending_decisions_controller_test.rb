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

  test "accept with a fields param only applies the selected fields" do
    sign_in_as users(:one)
    @pending.update!(
      kind: "enrichment_edition_mismatch",
      payload: {
        "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb",
        "fields" => [
          { "field" => "publisher", "current_value" => "St Martins Pr", "proposed" => "HarperVoyager" },
          { "field" => "format", "current_value" => nil, "proposed" => "hardcover" }
        ]
      }
    )

    post accept_pending_decision_url(@pending), params: { fields: [ "publisher" ] }, as: :turbo_stream

    assert_response :success
    assert_equal "HarperVoyager", @edition.reload.publisher
    assert_nil @edition.format
  end

  test "an edition_mismatch cover conflict end to end: show renders the comparison, accept attaches, reject purges" do
    sign_in_as users(:one)
    @edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
    @edition.candidate_cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
    @pending.update!(
      kind: "enrichment_edition_mismatch",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb", "fields" => [ { "field" => "cover_image" } ] }
    )

    get pending_decision_url(@pending)
    assert_response :success
    assert_select "img", minimum: 2

    post accept_pending_decision_url(@pending), as: :turbo_stream

    assert_response :success
    assert_equal "new-bytes", @edition.reload.cover_image.download
    assert_not @edition.candidate_cover_image.attached?
  end

  test "reread_conflict shows the payload's title/author and accept opens a new Reading" do
    sign_in_as users(:one)
    work = Work.create!(title: "Neuromancer", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work: work, edition: edition)
    Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2010, 5, 1))
    pending = PendingDecision.create!(
      kind: "reread_conflict",
      payload: { "goodreads_book_id" => "1", "title" => "Neuromancer", "author_name" => "William Gibson", "work_id" => work.id, "edition_id" => edition.id, "date_started" => "2026-08-01" }
    )

    get pending_decision_url(pending)
    assert_response :success
    assert_select "h1", text: "Neuromancer"
    assert_select "body", /William Gibson/

    post accept_pending_decision_url(pending), as: :turbo_stream

    assert_response :success
    assert_equal 2, work.readings.count
    assert_equal "accepted", pending.reload.status
  end
end

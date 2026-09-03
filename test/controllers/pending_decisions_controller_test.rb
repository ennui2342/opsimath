require "test_helper"

class PendingDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @edition = Edition.create!(publisher: "St Martins Pr")
    work = Work.create!(title: "The Gold Coast", literary_form: "novel")
    EditionContent.create!(work: work, edition: @edition)
    # field_diffs derives current/proposed live from the entity's column
    # plus this EnrichmentRecord — one record covers every field any test
    # below names, since they all share the same (entity, "isfdb") pair.
    EnrichmentRecord.create!(
      entity: @edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {},
      fields: { "publisher" => "HarperVoyager", "format" => "hardcover" }
    )
    @pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
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

  test "index labels an entity-less kind (reread_conflict) from the payload title, not 'unknown entity'" do
    sign_in_as users(:one)
    PendingDecision.create!(kind: "reread_conflict", payload: {
      "title" => "Downbelow Station", "author_name" => "C.J. Cherryh", "work_id" => 1, "edition_id" => 2, "date_started" => "2026-09-03"
    })

    get pending_decisions_url

    assert_select "a", text: /Downbelow Station/
    assert_select "body", { text: /Unknown entity/, count: 0 }
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
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "fields" => [ "format" ], "source" => "isfdb" }
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
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb", "fields" => [ "publisher", "format" ] }
    )

    post accept_pending_decision_url(@pending), params: { fields: [ "publisher" ] }, as: :turbo_stream

    assert_response :success
    assert_equal "HarperVoyager", @edition.reload.publisher
    assert_nil @edition.format
  end

  test "an edition_mismatch cover conflict end to end: show renders the comparison, accept attaches the source's cover" do
    sign_in_as users(:one)
    @edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
    source_record = EnrichmentRecord.latest(entity: @edition, provider: "isfdb")
    source_record.cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
    @pending.update!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb", "fields" => [ "cover_image" ] }
    )

    get pending_decision_url(@pending)
    assert_response :success
    assert_select "img", minimum: 2

    post accept_pending_decision_url(@pending), as: :turbo_stream

    assert_response :success
    assert_equal "new-bytes", @edition.reload.cover_image.download
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

  test "enrichment_printing_choice shows a card per printing with a radio, and accept commits the picked one" do
    sign_in_as users(:one)
    edition = Edition.create!(publisher: "Wrong On File")
    work = Work.create!(title: "The Anubis Gates", literary_form: "novel")
    EditionContent.create!(work: work, edition: edition)
    pending = PendingDecision.create!(kind: "enrichment_printing_choice", payload: {
      "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "isbn" => "0586065504",
      "candidates" => [
        { "_isfdb_pub_id" => 35244, "publisher" => "HarperCollins (UK)", "publish_date" => "1993-10", "binding" => "pb", "page_count" => 464 },
        { "_isfdb_pub_id" => 35246, "publisher" => "Triad Grafton", "publish_date" => "1986-05", "binding" => "pb", "page_count" => 464 }
      ]
    })
    pending.candidate_covers.attach(io: StringIO.new("cover"), filename: "35246.jpg", content_type: "image/jpeg")

    get pending_decision_url(pending)
    assert_response :success
    assert_select "h1", text: "The Anubis Gates"
    assert_select "input[type=radio][name='pub_id'][value=?][checked]", "35244"
    assert_select "input[type=radio][name='pub_id'][value=?]", "35246"
    assert_select "input[type=checkbox][name='fields[]'][value=publisher]"
    assert_select "img" # the 1986 printing's downloaded cover

    post accept_pending_decision_url(pending),
      params: { pub_id: "35246", fields: %w[publisher publish_date] }, as: :turbo_stream

    assert_response :success
    assert_equal "Triad Grafton", edition.reload.publisher
    assert_equal "1986-05", edition.publish_date
    assert_equal "accepted", pending.reload.status
  end
end

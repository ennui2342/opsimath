require "application_system_test_case"

class PendingDecisionsTest < ApplicationSystemTestCase
  setup do
    @edition = Edition.create!(publisher: "St Martins Pr")
    work = Work.create!(title: "The Gold Coast", literary_form: "novel")
    EditionContent.create!(work: work, edition: @edition)
    # field_diffs derives current/proposed live from the entity's column
    # plus this EnrichmentRecord — one record covers both tests below,
    # since they share the same (entity, "isfdb") pair.
    EnrichmentRecord.create!(
      entity: @edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {},
      fields: { "publisher" => "HarperVoyager", "format" => "hardcover" }
    )
    @pending = PendingDecision.create!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
    )

    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    # The login form submits via Turbo Drive (async), so click_on returns
    # before the redirect actually lands — wait for real post-login content
    # (an assertion, unlike a raw `visit`, retries until it's true) so the
    # next `visit` below can't race ahead of the session cookie being set.
    assert_text "Pending decisions"
  end

  test "reviewing and accepting a pending decision updates the record in place" do
    visit pending_decisions_path
    click_on "The Gold Coast"

    assert_text "St Martins Pr"
    assert_text "HarperVoyager"

    click_on "Accept (A)"

    assert_text "All caught up"
    assert_equal "HarperVoyager", @edition.reload.publisher
    assert_equal "accepted", @pending.reload.status
  end

  test "unchecking a field on a bundled edition mismatch excludes it from what gets applied" do
    @pending.update!(
      kind: "enrichment_conflict",
      payload: { "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb", "fields" => [ "publisher", "format" ] }
    )

    visit pending_decision_path(@pending)
    assert_text "St Martins Pr"

    uncheck "field_format"
    click_on "Accept (A)"

    assert_text "All caught up"
    @edition.reload
    assert_equal "HarperVoyager", @edition.publisher # checked, applied
    assert_nil @edition.format # unchecked, excluded
  end
end

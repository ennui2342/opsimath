require "test_helper"

class EditionMetadataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @work = Work.create!(title: "Crossfire", literary_form: "novel")
    @edition = Edition.create!(publisher: "St Martins Pr", format: "hardcover")
    EditionContent.create!(work: @work, edition: @edition)
    EnrichmentRecord.create!(
      entity: @edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
      raw_payload: {}, fields: { "publisher" => "Tor Books" }
    )
  end

  test "redirects to login when not authenticated" do
    get edition_metadata_url(@edition)
    assert_redirected_to new_session_path
  end

  test "show renders the reference card and a selectable card per source" do
    sign_in_as users(:one)

    get edition_metadata_url(@edition)

    assert_response :success
    assert_select "h1"
    assert_select "body", /St Martins Pr/
    assert_select "input[type=checkbox][name='field_picks[]'][value='isfdb:publisher']"
  end

  test "update applies the picked field and redirects to the book page" do
    sign_in_as users(:one)

    patch edition_metadata_url(@edition), params: { field_picks: [ "isfdb:publisher" ] }

    assert_redirected_to work_url(@work)
    assert_equal "Tor Books", @edition.reload.publisher
    follow_redirect!
    assert_select "body", /Updated Publisher/
  end

  test "update with nothing picked leaves the edition untouched" do
    sign_in_as users(:one)

    patch edition_metadata_url(@edition), params: {}

    assert_redirected_to work_url(@work)
    assert_equal "St Martins Pr", @edition.reload.publisher
  end

  test "an invalid pick redirects back to the metadata page with an alert" do
    sign_in_as users(:one)

    patch edition_metadata_url(@edition), params: { field_picks: [ "isfdb:page_count" ] }

    assert_redirected_to edition_metadata_url(@edition)
    assert_equal "St Martins Pr", @edition.reload.publisher
  end
end

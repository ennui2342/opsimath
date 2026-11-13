require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the home page: currently reading with Finished, the year, up next, and Mark's own activity" do
    ReadingGoal.create!(year: Date.current.year, target: 78)
    work = Work.create!(title: "Slow Gods", literary_form: "novel")
    edition = Edition.create!(page_count: 448)
    EditionContent.create!(work:, edition:)
    Copy.create!(edition:, disposition: "owned")
    reading = Reading.create!(work:, edition:, status: "reading", date_started: Date.current - 18)
    CatalogueEvent.create!(kind: "reading", origin: "web", work:, summary: "Slow Gods: started reading")
    CatalogueEvent.create!(kind: "series", origin: "work_series_sync", summary: "Filed in a series by the nightly job")

    get root_url

    assert_response :success
    assert_select "[data-home=reading] [data-card-title]", text: "Slow Gods"
    assert_select "form[action=?] button", work_reading_path(work, reading), text: "Finished"
    assert_match "0 of 78 books", response.body
    assert_select "[data-home=river] a", text: "Slow Gods: started reading"
    assert_no_match "Filed in a series by the nightly job", response.body # his own actions only

    patch work_reading_url(work, reading), params: { reading: { status: "completed" }, return_to: root_path }
    assert_redirected_to root_path
    assert reading.reload.completed?
  end

  test "the goal can be set, and a recommendation put off" do
    patch home_goal_url, params: { target: 52 }
    assert_equal 52, ReadingGoal.find_by(year: Date.current.year).target

    work = Work.create!(title: "Later", literary_form: "novel")
    post home_dismiss_url, params: { work_id: work.id }
    assert RecommendationDismissal.find_by(work:).until > 29.days.from_now
  end
end

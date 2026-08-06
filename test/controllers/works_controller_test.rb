require "test_helper"

class WorksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @work = Work.create!(title: "Neuromancer", literary_form: "novel")
    edition = Edition.create!(publisher: "Ace Books", publish_date: "1984")
    EditionContent.create!(work: @work, edition: edition)
    contributor = Contributor.create!(name: "William Gibson")
    WorkContributor.create!(work: @work, contributor: contributor, role: "author")
  end

  test "redirects to login when not authenticated" do
    get works_url
    assert_redirected_to new_session_path
  end

  test "index lists works" do
    sign_in_as users(:one)

    get works_url

    assert_response :success
    assert_select "a", text: /Neuromancer/
  end

  test "show renders the work's title, author, and edition" do
    sign_in_as users(:one)

    get work_url(@work)

    assert_response :success
    assert_select "h1", text: "Neuromancer"
    assert_select "body", /William Gibson/
    assert_select "body", /Ace Books/
  end
end

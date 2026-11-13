require "test_helper"

class WorksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @work = Work.create!(title: "Neuromancer", literary_form: "novel")
    @edition = Edition.create!(format: "paperback", format_detail: "mass_market", publisher: "Ace Books", publish_date: "1984")
    EditionContent.create!(work: @work, edition: @edition)
    EditionIdentifier.create!(edition: @edition, id_type: "isfdb", value: "55210")
    Copy.create!(edition: @edition, disposition: "owned")
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
    assert_select "body", /Mass market/
    assert_select "body", /Ace Books · 1984/
    assert_select "body", /Owned/
    assert_select "a[href=?]", "https://www.isfdb.org/cgi-bin/pl.cgi?55210", text: "55210"
  end

  test "the header search finds books by title and author word starts, folding punctuation" do
    sign_in_as users(:one)
    asimov = Contributor.create!(name: "Isaac Asimov")
    %w[Foundation Foundation\ and\ Earth].each do |title|
      Work.create!(title:, literary_form: "novel").work_contributors.create!(contributor: asimov, role: "author")
    end
    Work.create!(title: "Cat’s Cradle", literary_form: "novel")

    get works_url(q: "found asim")
    assert_select "[data-card]", count: 2
    assert_select "a", text: /Foundation and Earth/

    get works_url(q: "cats cradle")
    assert_redirected_to work_path(Work.find_by!(title: "Cat’s Cradle"))
  end

  test "the header search finds a book by ISBN, and offers to look up what isn't there" do
    sign_in_as users(:one)
    work = Work.create!(title: "Crossfire", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work:, edition:)
    edition.edition_identifiers.create!(id_type: "isbn13", value: "9780765304674")

    get works_url(q: "0-7653-0467-8")
    assert_redirected_to work_path(work)

    get works_url(q: "zzzz nothing")
    assert_select "a[href=?]", add_book_path(q: "zzzz nothing")
  end

  test "the Books list sorts; the Reading view lists most recently started first, with when and how long" do
    sign_in_as users(:one)
    older = Work.create!(title: "Aardvark", literary_form: "novel")
    newer = Work.create!(title: "Zebra", literary_form: "novel")
    [ [ older, 100 ], [ newer, 5 ] ].each do |work, days|
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Reading.create!(work:, edition:, status: "reading", date_started: Date.current - days)
    end

    get works_url(filter: "reading")

    titles = css_select("[data-card-title]").map { |t| t.text.strip }
    assert_operator titles.index("Zebra"), :<, titles.index("Aardvark")
    assert_select "[data-book-detail]", text: /open 100 days/

    get works_url(filter: "reading", sort: "title")
    titles = css_select("[data-card-title]").map { |t| t.text.strip }
    assert_operator titles.index("Aardvark"), :<, titles.index("Zebra")
  end
end

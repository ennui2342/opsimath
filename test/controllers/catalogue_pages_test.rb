require "test_helper"

# Author, series and publisher pages, linked from the book page.
class CataloguePagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @gibson = Contributor.create!(name: "William Gibson", died_date: nil)
    @sprawl = Series.create!(name: "Sprawl")
    @books = [ [ "Neuromancer", 1984, 1, "Ace Books" ], [ "Count Zero", 1986, 2, "Ace" ], [ "Mona Lisa Overdrive", 1988, 3, "Grafton" ] ].map do |title, year, pos, pub|
      work = Work.create!(title:, literary_form: "novel", original_publication_year: year)
      work.work_contributors.create!(contributor: @gibson, role: "author")
      work.work_series.create!(series: @sprawl, position: pos)
      edition = Edition.create!(publisher: pub, publish_date: year.to_s)
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "owned") unless title == "Count Zero"
      work
    end
  end

  test "the book page links its author, series and publisher" do
    get work_url(@books.first)

    assert_select "a[href=?]", author_path(@gibson), text: "William Gibson"
    assert_select "a[href=?]", series_path(@sprawl), text: "Sprawl"
    assert_select "a[href=?]", publisher_path(name: "Ace Books"), text: "Ace Books"
  end

  test "an author's page lists the books Mark owns first, then the rest, each by date" do
    get author_url(@gibson)

    assert_select "h1", "William Gibson"
    assert_select "h2", text: "Your books"
    assert_equal [ "Neuromancer", "Mona Lisa Overdrive", "Count Zero" ], css_select("[data-card-title]").map { |t| t.text.strip }
    assert_no_match "Not in your catalogue", response.body
    assert_match "3 books · 2 owned", response.body
  end

  test "a series page lists its books in series order, numbered" do
    get series_url(@sprawl)

    assert_equal %w[#1 #2 #3], css_select("[data-card-number]").map { |s| s.text.strip }
  end

  test "a publisher's page takes the imprint's spellings together" do
    get publisher_url(name: "Ace")

    assert_equal [ "Neuromancer", "Count Zero" ], css_select("[data-card-title]").map { |t| t.text.strip }
    assert_match "as Ace Books (1), Ace (1)", response.body.gsub(/\s+/, " ")
  end

  test "remove a book from its page" do
    work = Work.create!(title: "Books of Blood Volume 1", literary_form: "collection")
    get work_url(work)
    assert_select "form[action=?] button", work_path(work), text: "Remove this book"

    delete work_url(work)

    assert_redirected_to works_path
    assert_not Work.exists?(work.id)
  end

  test "an author's page adds their ISFDB bibliography: books Mark doesn't have, with Want it; translations and retitlings left out" do
    @gibson.update!(isfdb_works_fetched_at: Time.current, isfdb_works: [
      { "_isfdb_title_id" => 101, "title" => "Neuromancer", "type" => "NOVEL", "language" => "eng", "publish_year" => 1984 },
      { "_isfdb_title_id" => 102, "title" => "Virtual Light", "type" => "NOVEL", "language" => "eng", "publish_year" => 1993, "series" => "Bridge", "_isfdb_series_num" => 1 },
      { "_isfdb_title_id" => 103, "title" => "Burning Chrome", "type" => "COLLECTION", "language" => "eng", "publish_year" => 1986 },
      { "_isfdb_title_id" => 104, "title" => "Neuromante", "type" => "NOVEL", "language" => "spa", "publish_year" => 1989 },
      { "_isfdb_title_id" => 105, "title" => "Neuromancer (UK)", "type" => "NOVEL", "language" => "eng", "variant_of" => 101 }
    ])
    @books.first.work_identifiers.create!(id_type: "isfdb_title", value: "101")

    get author_url(@gibson)

    assert_select "h2", text: "Novels"
    assert_select "h2", text: "Collections"
    assert_no_match(/Neuromante|Neuromancer \(UK\)/, response.body)
    assert_select "form[action=?]", want_title_author_path(@gibson), count: 2 # Virtual Light, Burning Chrome

    post want_title_author_url(@gibson), params: { title_id: 102 }
    work = WorkIdentifier.find_by!(id_type: "isfdb_title", value: "102").work
    assert_equal [ "Virtual Light", [ "William Gibson" ] ], [ work.title, work.authors.map(&:name) ]
    assert work.want
  end

  test "the artist page's star makes an artist a favourite, or not" do
    post artist_favourite_url, params: { name: "Peter Elson", on: "1" }
    assert_includes CollectingProfile.current.favourite_artists, "Peter Elson"

    post artist_favourite_url, params: { name: "Peter Elson", on: "0" }
    profile = CollectingProfile.current
    assert_not_includes profile.favourite_artists, "Peter Elson"
    assert_equal [ [], [ "Peter Elson" ] ], [ profile.favourite_artists_always, profile.favourite_artists_never ]
  end

  test "an owned edition's panel offers wanting it in better condition, and asking puts that printing on the wishlist" do
    work = @books.first
    edition = work.editions.first
    edition.edition_identifiers.create!(id_type: "isfdb", value: "4242")

    get work_url(work)
    assert_select "form[action=?] button", better_copy_work_edition_path(work, edition), text: "Want this edition in better condition"

    post better_copy_work_edition_url(work, edition)

    assert_redirected_to work_path(work)
    assert_equal [ 4242 ], work.reload.want.printing_override_ids
  end

  test "web pages load the web app's stylesheets, never the pocket app's (its bare header rule broke the masthead)" do
    get work_url(@books.first)

    hrefs = css_select("link[rel=stylesheet]").map { |l| l["href"] }
    assert hrefs.any? { |h| h.include?("tailwind") }
    assert hrefs.none? { |h| h.include?("pocket") }, hrefs.inspect
  end

  test "a book whose ISFDB title shares nothing with its own is a pending decision: keep mine, or take ISFDB's" do
    work = @books.first
    work.update!(isfdb_main_title: "The Sprawl Trilogy")

    assert_equal 1, TitleCleanup.ask
    assert_equal 0, TitleCleanup.ask # asked once
    decision = PendingDecision.pending.find_by!(kind: TitleCleanup::QUESTION)
    assert_equal "Neuromancer", decision.display_title

    get pending_decision_url(decision)
    assert_select "span", text: "Wrong ISFDB link?"
    assert_match "The Sprawl Trilogy", response.body

    post reject_pending_decision_url(decision)
    assert_equal [ "Neuromancer", "manual" ], [ work.reload.title, work.field_sources["title"] ]
    assert_equal 0, TitleCleanup.ask # Mark's title now: never asked again
  end

  test "a title question no longer suspect is closed; accepting takes ISFDB's title" do
    work = @books.first
    work.update!(isfdb_main_title: "The Sprawl Trilogy")
    TitleCleanup.ask
    decision = PendingDecision.pending.find_by!(kind: TitleCleanup::QUESTION)

    post accept_pending_decision_url(decision)
    assert_equal "The Sprawl Trilogy", work.reload.title

    other = @books.second
    other.update!(isfdb_main_title: "Burning Chrome Stories")
    TitleCleanup.ask
    other.update!(isfdb_main_title: other.title) # its link fixed
    TitleCleanup.ask
    assert_equal 0, PendingDecision.pending.where(kind: TitleCleanup::QUESTION).count
  end

  test "the cog sets the book's title as Mark's own" do
    edition = @books.first.editions.first

    get edition_metadata_url(edition)
    assert_select "form[action=?]", title_edition_metadata_path(edition)

    patch title_edition_metadata_url(edition), params: { title: "Neuromancer", custom_title: "Neuromancer (Ace Special)" }

    assert_redirected_to work_path(@books.first)
    assert_equal [ "Neuromancer (Ace Special)", "manual" ], [ @books.first.reload.title, @books.first.field_sources["title"] ]
  end

  test "a book found by a title it was known by before; an edition printed under another title says so" do
    work = @books.first
    edition = work.editions.first
    TitleCleanup.retitle(work, "Sprawl One", source: "isfdb")
    edition.edition_identifiers.create!(id_type: "isfdb", value: "99")
    work.provider_editions.create!(provider: "isfdb", provider_id: "99", title: "Neuromancer")

    get works_url(q: "neuromancer")
    assert_redirected_to work_path(work)

    get work_url(work)
    assert_select "p", text: "as Neuromancer"
  end

  test "the book search finds a book by ISFDB's other titles for it — the title an edition was printed under" do
    work = @books.first
    work.update!(isfdb_variant_titles: [ "Neuromante Judgement" ])

    get works_url(q: "neuromante judgement")

    assert_redirected_to work_path(work)
  end
end

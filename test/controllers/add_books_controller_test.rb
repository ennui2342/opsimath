require "test_helper"

class AddBooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    isfdb = ENV.fetch("ISFDB_ADAPTER_URL") # the environment's own adapter URL — stubbed, never reached
    stub_request(:get, %r{https://covers\.test/.*}).to_return(status: 200, body: File.binread(Rails.root.join("test/fixtures/files/cover.png")),
                                                             headers: { "Content-Type" => "image/png" })
    pub = { "_isfdb_pub_id" => 55, "_isfdb_title_id" => 1911, "title" => "Crossfire", "authors" => [ "Nancy Kress" ],
            "publisher" => "Tor", "publish_date" => "2003-12", "binding" => "hc", "isbn_13" => "9780765304674", "isbn_10" => "",
            "cover_url" => "https://covers.test/55.png" }
    stub_request(:get, "#{isfdb}/search").with(query: hash_including({})).to_return(status: 200, body: [ pub ].to_json)
    stub_request(:get, "#{isfdb}/isbn/9780765304674/editions").to_return(status: 200, body: [ pub ].to_json)
    stub_request(:get, %r{openlibrary\.org/search\.json}).to_return(status: 200, body: { docs: [] }.to_json)
  end

  def found_token
    get add_book_url(q: "crossfire kress")
    css_select("a").map { |a| a["href"] }.find { |h| h.to_s.include?("found=") }.then { |h| Rack::Utils.parse_query(URI(h).query)["found"] }
  end

  test "the search box carries a barcode scanner, hidden until the browser has one" do
    get add_book_url

    assert_select "form[data-controller=barcode-scan]" do
      assert_select "button[hidden][data-action='barcode-scan#open']", text: "Scan barcode"
      assert_select "[data-barcode-scan-target=overlay][hidden] video"
    end
    assert_select "form[data-barcode-scan-secure-url-value=?][data-barcode-scan-autostart-value=false]",
                  "#{Rails.application.config.x.public_url}/add?scan=1"

    get add_book_url(scan: 1)
    assert_select "form[data-barcode-scan-autostart-value=true]"
  end

  test "search shows each work with choose-edition and want-it" do
    get add_book_url(q: "crossfire kress")

    assert_response :success
    assert_select "p", text: "Crossfire"
    assert_select "a", text: "Choose edition"
    assert_select "button", text: "Want it"
  end

  test "choose the edition, own it and say it's read: work, edition, copy and reading" do
    token = found_token
    get add_book_editions_url(found: token)
    assert_response :success
    card = css_select("input[type=radio][name=card]").sole["value"]

    post add_book_url, params: { found: token, card:, own: "1", reading_status: "read", date_finished: "2026-11-01", rating: "5" }

    work = Work.find_by!(title: "Crossfire")
    assert_redirected_to work_path(work)
    edition = work.editions.sole
    assert_equal [ "Tor", "hardcover" ], [ edition.publisher, edition.format ]
    assert edition.copies.sole.owned?
    assert_equal [ "completed", 5 ], [ work.readings.sole.status, work.readings.sole.rating.to_i ]
  end

  test "want it: the work on the wishlist, no edition" do
    post add_book_url, params: { found: found_token, intent: "want" }

    work = Work.find_by!(title: "Crossfire")
    assert work.want
    assert_empty work.editions
  end

  test "a wanted book's edition picker reads its known editions, then getting it retires the want" do
    want = create_want(title: "Crossfire", author: "Nancy Kress")
    want.work.provider_editions.create!(provider: "isfdb", provider_id: "55", publisher: "Tor", binding: "hc", isbn13: "9780765304674")

    get add_book_editions_url(work_id: want.work_id)
    card = css_select("input[type=radio][name=card]").sole["value"]
    post add_book_url, params: { work_id: want.work_id, card:, own: "1" }

    assert_redirected_to work_path(want.work)
    assert_not Want.exists?(want.id)
    assert_equal 1, want.work.reload.editions.count
  end

  test "a catalogued work's picker fetches every Open Library work id it holds" do
    work = Work.create!(title: "Crossfire", literary_form: "novel")
    %w[OL1W OL2W].each { |id| work.work_identifiers.create!(id_type: "openlibrary_work", value: id) }
    %w[OL1W OL2W].each_with_index do |id, i|
      stub_request(:get, "https://openlibrary.org/works/#{id}/editions.json").with(query: hash_including({}))
        .to_return(status: 200, body: { entries: [ { key: "/books/OL#{i}M", publishers: [ "Pub #{i}" ], isbn_13: [ "978076530467#{i}" ] } ] }.to_json)
    end

    get add_book_editions_url(work_id: work.id)

    assert_select "input[type=radio][name=card]", 2
  end

  test "a tampered or expired token is refused" do
    post add_book_url, params: { found: "nonsense", intent: "want" }

    assert_redirected_to add_book_path
    assert_equal 0, Want.count
  end
end

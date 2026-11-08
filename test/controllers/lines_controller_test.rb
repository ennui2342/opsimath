require "test_helper"

class LinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    Rails.cache.clear
    @work = Work.create!(title: "The Female Man", literary_form: "novel")
    @work.work_contributors.create!(contributor: Contributor.create!(name: "Joanna Russ"), role: "author")
    @edition = Edition.create!(publisher: "The Women's Press", publish_date: "1985")
    EditionContent.create!(work: @work, edition: @edition)
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "500")
    Copy.create!(edition: @edition, disposition: "owned")
    @work.provider_editions.create!(provider: "isfdb", provider_id: "500", binding: "pb", publisher: "The Women's Press",
                                    pub_series_id: 77, pub_series_name: "The Women's Press Science Fiction", pub_series_num: "2")
    @isfdb = ENV.fetch("ISFDB_ADAPTER_URL")
  end

  def pub(id, num, title, title_id) = { "_isfdb_pub_id" => id, "_isfdb_title_id" => title_id, "pub_series_num" => num, "title" => title,
                                        "authors" => [ "X" ], "publisher" => "The Women's Press", "publish_date" => "1985", "cover_url" => "" }

  test "the book page names the edition's line and links to it" do
    get work_url(@work)

    assert_select "a[href=?]", line_path(77), text: "The Women's Press Science Fiction"
    assert_match "#2", response.body
  end

  test "the line page: every number, which is yours and which is missing" do
    stub_request(:get, "#{@isfdb}/pubseries/77").to_return(status: 200, body: {
      id: 77, name: "The Women's Press Science Fiction",
      publications: [ pub(499, "1", "Walk to the End of the World", 900), pub(500, "2", "The Female Man", 901) ]
    }.to_json)

    get line_url(77)

    assert_select "h1", "The Women's Press Science Fiction"
    assert_match "1 of 2 printings yours", response.body
    assert_select "span", text: "Missing"
    assert_select "span", text: "Yours"
  end

  test "before the mirror has line names: the printings already known, and a note" do
    stub_request(:get, "#{@isfdb}/pubseries/77").to_return(status: 503, body: { detail: "publication series not imported yet" }.to_json)

    get line_url(77)

    assert_select "h1", "The Women's Press Science Fiction"
    assert_match "full line arrives with the next ISFDB mirror refresh", response.body
  end

  test "collect a line, say not this one, collect again, stop" do
    stub_request(:get, "#{@isfdb}/pubseries/77").to_return(status: 200, body: { id: 77, name: "The Women's Press Science Fiction",
                                                                              publications: [ pub(499, "1", "Walk", 900), pub(500, "2", "The Female Man", 901) ] }.to_json)
    assert_enqueued_with(job: LineWantsJob) { post collect_line_url(77) }
    line_want = LineWant.find_by!(pub_series_id: 77)

    get line_url(77)
    assert_select "button", text: "Not this one", count: 1 # #2 is yours

    post exclude_line_url(77), params: { pub_id: 499 }
    assert_equal [ 499 ], line_want.reload.excluded_pub_ids
    post include_line_url(77), params: { pub_id: 499 }
    assert_empty line_want.reload.excluded_pub_ids

    delete collect_line_url(77)
    assert_not LineWant.exists?(line_want.id)
  end
end

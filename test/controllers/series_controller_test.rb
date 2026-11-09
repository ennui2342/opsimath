require "test_helper"

class SeriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    Rails.cache.clear
    @isfdb = ENV.fetch("ISFDB_ADAPTER_URL")
    @series = Series.create!(name: "The Snow Queen Cycle", isfdb_series_id: 448)
    @summer = Work.create!(title: "The Summer Queen", literary_form: "novel")
    @summer.work_identifiers.create!(id_type: "isfdb_title", value: "1086")
    WorkSeries.create!(work: @summer, series: @series, position: 3)
    edition = Edition.create!
    EditionContent.create!(work: @summer, edition:)
    Copy.create!(edition:, disposition: "owned")
    stub_request(:get, "#{@isfdb}/series/448/volumes").to_return(status: 200, body: [
      volume(1180, 1, "The Snow Queen"), volume(793, 2, "World's End"), volume(1086, 3, "The Summer Queen"),
      volume(2074977, 0, "Le cycle de Tiamat: Volume 1", language: "fre")
    ].to_json)
  end

  def volume(id, position, title, language: "eng") = { external_id: id.to_s, position:, title:, release_date: "1980-04",
                                                        cover_url: "", language:, authors: [ "Joan D. Vinge" ] }

  test "every book in the series, in order, with a Want it for those Mark doesn't have; a translation's omnibus left out" do
    get series_url(@series)

    assert_equal [ "The Snow Queen", "World's End", "The Summer Queen" ], css_select("[data-card-title]").map { |t| t.text.strip }
    assert_select "[data-card=edition] a[href=?]", work_path(@summer)
    assert_select "form[action=?]", want_volume_series_path(@series), count: 2
    assert_no_match "Tiamat", response.body
  end

  test "Want it: the book joins the catalogue, the series and the wishlist" do
    post want_volume_series_url(@series), params: { title_id: 1180 }

    work = WorkIdentifier.find_by!(id_type: "isfdb_title", value: "1180").work
    assert_equal [ "The Snow Queen", 1 ], [ work.title, work.work_series.sole.position.to_i ]
    assert work.want
  end

  test "collecting the series wants every book Mark doesn't have; not this one sticks; stopping removes them" do
    post collect_series_url(@series)
    series_want = @series.reload.series_want
    assert_equal 2, SeriesWants::Sync.run(series_want)
    assert_equal 2, series_want.wants.count

    post exclude_series_url(@series), params: { title_id: 793 }
    assert_equal [ 793 ], series_want.reload.excluded_title_ids
    assert_equal 1, series_want.wants.count
    assert_equal 0, SeriesWants::Sync.run(series_want)

    delete collect_series_url(@series)
    assert_not SeriesWant.exists?(series_want.id)
    assert_nil WorkIdentifier.find_by(id_type: "isfdb_title", value: "1180")&.work&.want
  end

  test "a series not yet matched to ISFDB shows the catalogue's books" do
    @series.update!(isfdb_series_id: nil)

    get series_url(@series)

    assert_select "[data-card]", count: 1
    assert_match "full series appears once it's matched to ISFDB", response.body
  end

  test "two ISFDB titles of the same book in a series list it once" do
    stub_request(:get, "#{@isfdb}/series/448/volumes").to_return(status: 200, body: [
      volume(1086, 3, "The Summer Queen"), volume(9999, 0, "The Summer Queen"), volume(1180, 1, "The Snow Queen")
    ].to_json)
    Rails.cache.clear

    get series_url(@series)

    assert_equal [ "The Snow Queen", "The Summer Queen" ], css_select("[data-card-title]").map { |t| t.text.strip }
  end
end

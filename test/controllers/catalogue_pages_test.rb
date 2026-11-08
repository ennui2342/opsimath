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

  test "an author's page lists their books in publication order with statuses" do
    get author_url(@gibson)

    assert_select "h1", "William Gibson"
    assert_equal [ "Neuromancer", "Count Zero", "Mona Lisa Overdrive" ], css_select("ul li span.block.font-medium").map(&:text)
    assert_match "3 books in your catalogue · 2 owned", response.body
  end

  test "a series page lists its books in series order, numbered" do
    get series_url(@sprawl)

    assert_equal %w[#1 #2 #3], css_select("ul li span.tabular-nums").map { |s| s.text.strip }
  end

  test "a publisher's page takes the imprint's spellings together" do
    get publisher_url(name: "Ace")

    assert_equal [ "Neuromancer", "Count Zero" ], css_select("ul li span.block.font-medium").map(&:text)
    assert_match "as Ace Books (1), Ace (1)", response.body.gsub(/\s+/, " ")
  end
end

require "test_helper"

class BookListWantsSyncTest < ActiveSupport::TestCase
  setup do
    @list = BookList.create!(key: "isfdb_award_category:7", name: "Clarke Award: Best Novel", short_name: "Clarke", kind: "award")
    [ [ 2019, "winner", "Rosewater", 10 ], [ 2019, "shortlisted", "Semiosis", 11 ], [ 2015, "winner", "Station Eleven", 12 ],
      [ 2019, "shortlisted", "Unmatched", nil ] ].each do |year, status, title, id|
      @list.entries.create!(year:, status:, title:, author: "Someone Writer", isfdb_title_id: id)
    end
    owned = Work.create!(title: "Station Eleven", literary_form: "novel")
    owned.work_identifiers.create!(id_type: "isfdb_title", value: "12")
    edition = Edition.create!
    EditionContent.create!(work: owned, edition:)
    Copy.create!(edition:, disposition: "owned")
  end

  def wanted_titles = Want.includes(:work).map { |w| w.work.title }.sort

  test "winners: only the winners Mark doesn't have; a book added for each, never an unmatched entry" do
    BookListWants::Sync.run(BookListWant.create!(book_list: @list, scope: "winners"))

    assert_equal [ "Rosewater" ], wanted_titles
    assert_equal "10", Work.find_by!(title: "Rosewater").work_identifiers.sole.value
  end

  test "the whole shortlist from a year; excluded books stay out; stopping removes what it added" do
    lw = BookListWant.create!(book_list: @list, scope: "shortlist", from_year: 2016, excluded_title_ids: [ 11 ])
    assert_equal 1, BookListWants::Sync.run(lw)
    assert_equal [ "Rosewater" ], wanted_titles

    lw.update!(excluded_title_ids: [])
    BookListWants::Sync.run(lw)
    assert_equal %w[Rosewater Semiosis], wanted_titles

    lw.stop!
    assert_empty wanted_titles
    assert_nil Work.find_by(title: "Semiosis") # a placeholder book goes with its want
  end

  test "progress: read and owned, and the years latest first with the winner first" do
    view = BookListView.for(@list)
    assert_equal [ 4, 1, 0 ], [ view.entries.size, view.owned, view.read ]
    assert_equal [ 2019, 2015 ], view.by_year.map(&:first)
    assert_equal "Rosewater", view.by_year.first.last.first.title
  end

  test "a book is found by another of its titles when the list's ISFDB title isn't the one it's linked to" do
    list = BookList.create!(key: "pringle_100", name: "Pringle", short_name: "Pringle 100", kind: "curated")
    list.entries.create!(title: "The Martian Chronicles", author: "Ray Bradbury", year: 1950, position: 3, status: "listed", isfdb_title_id: 999)
    mine = Work.create!(title: "The Silver Locusts", literary_form: "collection")
    mine.work_contributors.create!(contributor: Contributor.create!(name: "Ray Bradbury"), role: "author")
    mine.work_alternate_titles.create!(title: "The Martian Chronicles")

    assert_equal mine, BookListView.for(list).entries.sole.work
  end
end

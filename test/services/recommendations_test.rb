require "test_helper"

class RecommendationsTest < ActiveSupport::TestCase
  setup do
    @today = Date.current
    @wells = Contributor.create!(name: "Martha Wells")
  end

  def book(title, form: "novel", pages: 300, author: @wells, acquired: @today - 400)
    work = Work.create!(title:, literary_form: form)
    work.work_contributors.create!(contributor: author, role: "author")
    edition = Edition.create!(page_count: pages)
    EditionContent.create!(work:, edition:)
    Copy.create!(edition:, disposition: "owned", acquired_date: acquired)
    work
  end

  def read(work, rating:, finished: @today - 30, started: finished - 10)
    Reading.create!(work:, edition: work.editions.first, status: "completed", rating:, date_finished: finished, date_started: started)
  end

  test "the next book of a series he loved, and an author he rates — each saying why; non-fiction left out" do
    series = Series.create!(name: "Murderbot")
    one = book("All Systems Red")
    two = book("Artificial Condition")
    WorkSeries.create!(work: one, series:, position: 1)
    WorkSeries.create!(work: two, series:, position: 2)
    read(one, rating: 5)
    read(book("Witch King"), rating: 5)
    book("The Element of Fire")
    book("A History of Robots", form: "nonfiction")
    other = Contributor.create!(name: "Someone Else")
    read(book("Meh", author: other), rating: 2)

    picks = Recommendations.new(stats: ReadingStats.new).picks(3)

    series_pick = picks.find { |p| p.reason == :series }
    assert_equal two, series_pick.work
    assert_match "Next in Murderbot", series_pick.detail
    assert_includes picks.map { |p| p.work.title }, "The Element of Fire"
    assert_not_includes picks.map { |p| p.work.title }, "A History of Robots"
    assert_equal picks.map(&:reason).uniq.size, picks.size # each for a different reason
  end

  test "a dragging read switches to quick wins: short, by an author he likes, not the dragging book's author" do
    north = Contributor.create!(name: "Claire North")
    slow = book("Slow Gods", pages: 448, author: north)
    Reading.create!(work: slow, edition: slow.editions.first, status: "reading", date_started: @today - 200)
    read(book("Witch King"), rating: 5)
    read(book("Network Effect"), rating: 5, finished: @today - 60)
    short = book("Home: Habitat, Range, Niche, Territory", form: "novella", pages: 50)
    book("The Gameshouse", pages: 120, author: north)

    recommender = Recommendations.new(stats: ReadingStats.new)
    assert recommender.quick_win?
    first = recommender.picks(3).first

    assert_equal [ short, :quick_win ], [ first.work, first.reason ]
    assert_match "A quick win", first.detail
  end

  test "Not now and Not for me keep a book out" do
    read(book("Witch King"), rating: 5)
    shelved = book("The Element of Fire")
    RecommendationDismissal.create!(work: shelved, until: 30.days.from_now)

    assert_not_includes Recommendations.new(stats: ReadingStats.new).picks(3).map(&:work), shelved
  end
end

require "test_helper"

class ReadingStatsTest < ActiveSupport::TestCase
  setup { @today = Date.new(2026, 11, 13) }

  def finish(finished, started: nil, pages: nil)
    work = Work.create!(title: "Book #{SecureRandom.hex(3)}", literary_form: "novel")
    edition = Edition.create!(page_count: pages)
    EditionContent.create!(work:, edition:)
    Reading.create!(work:, edition:, status: "completed", date_finished: finished, date_started: started)
  end

  test "the year against its goal: done, where he'd be by now, and the weekly rate to make it" do
    ReadingGoal.create!(year: 2026, target: 78)
    42.times { |i| finish(Date.new(2026, 1, 1) + (i * 7)) }
    finish(Date.new(2025, 6, 1)) # last year: not counted

    goal = ReadingStats.new(today: @today).goal

    assert_equal [ 42, 78 ], [ goal.done, goal.target ]
    assert_equal 68, goal.expected # 78 × 317/365
    assert_equal 26, goal.behind
    assert_equal 5.3, goal.per_week # 36 to go over 6.9 weeks
  end

  test "pace, days a book, pages a day, and a read that's dragging" do
    finish(@today - 10, started: @today - 20, pages: 200) # 10 days, 20 pages/day
    finish(@today - 30, started: @today - 40, pages: 300)
    finish(@today - 400, started: @today - 410, pages: 100)
    finish(@today - 500, started: @today - 540) # a slow one: his 90th percentile is 40 days
    stats = ReadingStats.new(today: @today)

    assert_equal 10, stats.median_days
    assert_equal 20.0, stats.pages_per_day
    assert_equal 0.2, stats.pace_recent # 2 in 12 weeks, to one decimal

    work = Work.create!(title: "Slow Gods", literary_form: "novel")
    edition = Edition.create!(page_count: 200)
    EditionContent.create!(work:, edition:)
    open = Reading.create!(work:, edition:, status: "reading", date_started: @today - 25)
    assert_equal 10, stats.expected_days(open)
    assert stats.dragging?(open) # 25 days open, 10 expected
    open.update!(date_started: @today - 15)
    assert_not stats.dragging?(open)
  end
end

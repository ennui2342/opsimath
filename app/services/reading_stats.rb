# Mark's reading, in numbers (docs/HOME.md, "The year" and "Dragging and
# slumps"): the year against its goal, his pace now and over the years,
# how long a book usually takes him, and whether an open read is dragging
# or he's in a slump. Finishes are completed readings with a finish date —
# rereads count.
class ReadingStats
  Goal = Struct.new(:year, :target, :done, :expected, :weeks_left, :per_week, keyword_init: true) do
    def behind = expected - done
    def ahead? = done >= expected
  end

  RECENT_WEEKS = 12
  SLUMP_DAYS = 60

  attr_reader :today

  def initialize(today: Date.current)
    @today = today
  end

  # [date_finished, date_started, pages] for every finish.
  def finishes
    @finishes ||= Reading.where(status: "completed").where.not(date_finished: nil).left_joins(:edition)
                         .pluck(:date_finished, :date_started, "editions.page_count")
  end

  def finished_in(year) = finishes.count { |finished, _, _| finished.year == year }

  # {year => books finished}, every year with a dated finish.
  def by_year = finishes.map { |finished, _, _| finished.year }.tally.sort.to_h

  def goal(year = today.year)
    target = ReadingGoal.find_by(year:)&.target or return
    done = finished_in(year)
    year_start, year_end = Date.new(year, 1, 1), Date.new(year, 12, 31)
    fraction = ((today - year_start + 1).to_f / (year_end - year_start + 1)).clamp(0, 1)
    weeks_left = [ (year_end - today).to_f / 7, 1.0 / 7 ].max
    Goal.new(year:, target:, done:, expected: (target * fraction).round, weeks_left: weeks_left.round(1),
             per_week: ([ target - done, 0 ].max / weeks_left).round(1))
  end

  # Books a week over the last `weeks` weeks.
  def pace(weeks)
    since = today - (weeks * 7)
    (finishes.count { |finished, _, _| finished > since } / weeks.to_f).round(1)
  end

  def pace_recent = pace(RECENT_WEEKS)
  def pace_year = pace(52)

  # Days from start to finish, for finishes with both dates.
  def durations
    @durations ||= finishes.filter_map { |finished, started, _| (finished - started).to_i if started && finished >= started }.sort
  end

  def median_days = percentile(durations, 0.5)
  def p75_days = percentile(durations, 0.75)
  def p90_days = percentile(durations, 0.9)

  # His pages a day: the median over finishes with both dates and a page count.
  def pages_per_day
    @pages_per_day ||= percentile(finishes.filter_map { |finished, started, pages|
      days = started && (finished - started).to_i
      pages.to_f / days if days&.positive? && pages&.positive?
    }.sort, 0.5)
  end

  # How long an open read should take him: its pages at his pace, else his
  # 75th-percentile days.
  def expected_days(reading)
    pages = reading.edition&.page_count
    return (pages / pages_per_day).ceil if pages&.positive? && pages_per_day&.positive?

    p75_days
  end

  def days_open(reading) = reading.date_started ? (today - reading.date_started).to_i : nil

  # Open more than twice as long as it should take, or longer than his
  # 90th percentile.
  def dragging?(reading)
    open = days_open(reading) or return false
    expected = expected_days(reading)
    (expected && open > 2 * expected) || (p90_days && open > p90_days)
  end

  # Fewer finishes in the last 60 days than his 12-month pace predicts.
  def slump?
    predicted = pace_year * SLUMP_DAYS / 7.0
    recent = finishes.count { |finished, _, _| finished > today - SLUMP_DAYS }
    predicted.positive? && recent < predicted * 0.6
  end

  private

  def percentile(sorted, fraction)
    return if sorted.empty?

    sorted[((sorted.size - 1) * fraction).round]
  end
end

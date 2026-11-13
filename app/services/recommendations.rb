# What to read next (docs/HOME.md, "Up next"): from the fiction Mark owns
# and hasn't finished, three picks chosen for different reasons, each
# saying why. Signals:
#
# - author affinity: his ratings of the author, shrunk towards his overall
#   mean by how few he's rated (a Bayesian average, PRIOR_WEIGHT reads of
#   prior) — two 5★ reads beat one, a single 4★ isn't over-weighted;
# - series momentum: the next unread book of a series he's read and liked,
#   more so the better he rated it and the more recently;
# - echoes: shares a series or subject with his 4–5★ reads of the last two
#   years;
# - fresh arrivals (acquired in the last 90 days) and long-shelved (years
#   on the shelf), each a gentle push;
# - quick-win mode (a read dragging, or a slump): short books by
#   high-affinity authors, away from the dragging book's author and form.
#
# Plain column queries throughout: the web pod has 768 MB.
class Recommendations
  Pick = Struct.new(:work, :edition, :reason, :detail, keyword_init: true)

  FICTION = %w[novel novella collection anthology omnibus].freeze
  PRIOR_WEIGHT = 2.0
  SHORT_PAGES = 250
  LONG_PAGES = 450

  def self.for(stats: ReadingStats.new, count: 3) = new(stats:).picks(count)

  def initialize(stats:)
    @stats = stats
    @today = stats.today
  end

  # -> up to `count` Picks, each for a different reason.
  def picks(count)
    order = quick_win? ? %i[quick_win series author echo fresh shelf] : %i[series author echo fresh shelf quick_win]
    chosen = []
    order.each do |reason|
      break if chosen.size >= count

      best = candidates.reject { |c| chosen.any? { |p| p.work.id == c[:work_id] } }
                       .filter_map { |c| (s = send(:"#{reason}_score", c)) && [ c, s ] }.max_by(&:last)
      chosen << pick_for(best.first, reason) if best
    end
    chosen
  end

  def quick_win? = @quick_win ||= (@stats.slump? || dragging.any?)

  # Open reads that are dragging.
  def dragging
    @dragging ||= Reading.where(status: %w[reading paused]).includes(:edition, work: { work_contributors: :contributor })
                         .select { |r| @stats.dragging?(r) }
  end

  private

  def pick_for(candidate, reason)
    work = Work.includes(work_contributors: :contributor).find(candidate[:work_id])
    edition = Edition.includes(:copies, :readings, :edition_identifiers, { cover_image_attachment: { blob: :variant_records } }).find(candidate[:edition_id])
    Pick.new(work:, edition:, reason:, detail: detail_for(candidate, reason))
  end

  def detail_for(c, reason)
    author = c[:author_ids].filter_map { |id| author_names[id] }.first
    case reason
    when :quick_win then "A quick win: #{[ ("#{c[:pages]} pages" if c[:pages]), (c[:form] == 'novella' ? 'a novella' : nil) ].compact.join(', ')}" +
                         (author && affinity(c) > 0 ? " · you rate #{author} #{format('%.1f', author_mean(c))}" : "")
    when :series then "Next in #{c[:series_name]}: you rated #{c[:series_read]} #{c[:series_read] == 1 ? 'book' : 'books'} of it #{format('%.1f', c[:series_rating])}★"
    when :author then "#{author}: you rate them #{format('%.1f', author_mean(c))} over #{author_count(c)} #{author_count(c) == 1 ? 'book' : 'books'}"
    when :echo then "Like #{c[:echo_of]}, which you loved"
    when :fresh then "New on your shelf — #{c[:acquired].strftime('%-d %B')}"
    when :shelf then "On your shelf since #{c[:acquired].year}"
    end
  end

  # --- scores (nil: not a candidate for that reason) -------------------

  def quick_win_score(c)
    return unless quick_win?
    return unless c[:form] == "novella" || (c[:pages] && c[:pages] <= SHORT_PAGES)
    return if (c[:author_ids] & dragging_author_ids).any?

    1 + (affinity(c) * 2) + (c[:form] == "novella" ? 0.3 : 0)
  end

  def series_score(c)
    return unless c[:series_next]

    (c[:series_rating] - mean) + (c[:series_recent] ? 0.5 : 0) + 0.5
  end

  def author_score(c)
    a = affinity(c)
    a if a > 0.3
  end

  def echo_score(c)
    c[:echo] if c[:echo]&.positive?
  end

  def fresh_score(c)
    return unless c[:acquired] && c[:acquired] > @today - 90

    ((90 - (@today - c[:acquired]).to_i) / 90.0) + affinity(c)
  end

  def shelf_score(c)
    return unless c[:acquired] && c[:acquired] < @today - (3 * 365)

    ((@today - c[:acquired]).to_i / 365.0 / 10) + affinity(c) - (c[:pages] && c[:pages] > LONG_PAGES ? 0.3 : 0)
  end

  # --- the data ----------------------------------------------------------

  def candidates
    @candidates ||= begin
      owned = Copy.where(disposition: "owned").joins(edition: :edition_contents)
                  .pluck("edition_contents.work_id", :edition_id, :acquired_date, "copies.created_at", "editions.page_count")
      dismissed = RecommendationDismissal.active.pluck(:work_id).to_set
      forms = Work.where(id: owned.map(&:first)).pluck(:id, :literary_form).to_h
      owned.group_by(&:first).filter_map do |work_id, rows|
        next if finished_ids.include?(work_id) || open_ids.include?(work_id) || dismissed.include?(work_id)
        next unless FICTION.include?(forms[work_id])

        _, edition_id, acquired, created, pages = rows.min_by { |r| r[2] || r[3].to_date }
        series = next_in_series[work_id]
        { work_id:, edition_id:, form: forms[work_id], pages:, acquired: acquired || created&.to_date,
          author_ids: authors_of[work_id] || [], series_next: !series.nil?, **(series || {}), **echo_for(work_id) }
      end
    end
  end

  def finished_ids = @finished_ids ||= Reading.where(status: "completed").distinct.pluck(:work_id).to_set
  def open_ids = @open_ids ||= Reading.where(status: %w[reading paused]).distinct.pluck(:work_id).to_set

  # {work_id => his latest rating}
  def ratings
    @ratings ||= Reading.where(status: "completed").where.not(rating: nil).order(:date_finished)
                        .pluck(:work_id, :rating).to_h.transform_values(&:to_f)
  end

  def mean = @mean ||= ratings.any? ? ratings.values.sum / ratings.size : 3.5

  def authors_of
    @authors_of ||= WorkContributor.where(role: "author").pluck(:work_id, :contributor_id)
                                   .group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  def author_names = @author_names ||= Contributor.where(id: authors_of.values.flatten.uniq).pluck(:id, :name).to_h

  # {contributor_id => [ratings of theirs]}
  def author_ratings
    @author_ratings ||= ratings.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(work_id, rating), out|
      Array(authors_of[work_id]).each { |a| out[a] << rating }
    end
  end

  def bayes(list) = ((PRIOR_WEIGHT * mean) + list.sum) / (PRIOR_WEIGHT + list.size)

  def best_author(c) = c[:author_ids].select { |a| author_ratings.key?(a) }.max_by { |a| bayes(author_ratings[a]) }

  def affinity(c) = (a = best_author(c)) ? bayes(author_ratings[a]) - mean : 0.0

  def author_mean(c) = (a = best_author(c)) ? author_ratings[a].sum / author_ratings[a].size : mean

  def author_count(c) = (a = best_author(c)) ? author_ratings[a].size : 0

  def dragging_author_ids = @dragging_author_ids ||= dragging.flat_map { |r| r.work.work_contributors.select { |wc| wc.role == "author" }.map(&:contributor_id) }

  # {work_id => series facts} for each series' next unread book after the
  # highest-numbered one he's finished.
  def next_in_series
    @next_in_series ||= begin
      rows = WorkSeries.joins(:series).where.not(position: nil).pluck(:work_id, :series_id, :position, "series.name")
      last_finished = Reading.where(status: "completed").group(:work_id).maximum(:date_finished)
      rows.group_by { |r| r[1] }.each_with_object({}) do |(_, members), out|
        read = members.select { |m| finished_ids.include?(m[0]) }
        next if read.empty?

        top = read.map { |m| m[2] }.max
        nxt = members.reject { |m| finished_ids.include?(m[0]) }.select { |m| m[2] > top }.min_by { |m| m[2] }
        next unless nxt

        rated = read.filter_map { |m| ratings[m[0]] }
        recent = read.filter_map { |m| last_finished[m[0]] }.max
        out[nxt[0]] = { series_name: nxt[3], series_read: read.size, series_rating: rated.any? ? rated.sum / rated.size : mean,
                        series_recent: recent.present? && recent > @today - 365 }
      end
    end
  end

  # His 4–5★ finishes of the last two years: series and subjects, weighted
  # by how rare each subject is.
  def loves
    @loves ||= Reading.where(status: "completed").where("rating >= 4").where("date_finished > ?", @today - (2 * 365))
                      .distinct.pluck(:work_id)
  end

  def subject_weights
    @subject_weights ||= begin
      counts = WorkSubject.group(:subject_id).count
      counts.transform_values { |n| 1.0 / Math.log2(n + 1) }
    end
  end

  def subjects_of
    @subjects_of ||= WorkSubject.pluck(:work_id, :subject_id).group_by(&:first).transform_values { |r| r.map(&:last).to_set }
  end

  def echo_for(work_id)
    mine = subjects_of[work_id] || Set.new
    best = loves.filter_map do |loved|
      shared = mine & (subjects_of[loved] || Set.new)
      score = shared.sum { |s| subject_weights[s].to_f }
      [ loved, score ] if score.positive?
    end.max_by(&:last)
    return {} unless best && best.last > 0.6

    { echo: best.last, echo_of: echo_titles[best.first] }
  end

  def echo_titles = @echo_titles ||= Work.where(id: loves).pluck(:id, :title).to_h
end

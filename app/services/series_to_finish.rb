# Series Mark has started but not finished (docs/HOME.md): at least one
# book of it finished, at least one not — by ISFDB's full volume list where
# the series is tied to ISFDB (SeriesVolumes), else the catalogue's own
# members. Ranked by how he rated the ones he read and how recently; only
# the top few are looked up against ISFDB (each a cached adapter call).
class SeriesToFinish
  Entry = Struct.new(:series, :read, :total, :rating, :next_entry, keyword_init: true)

  def self.top(limit = 5, today: Date.current) = new(today:).top(limit)

  def initialize(today:)
    @today = today
  end

  def top(limit)
    finished = Reading.where(status: "completed").group(:work_id).maximum(:date_finished)
    ratings = Reading.where(status: "completed").where.not(rating: nil).pluck(:work_id, :rating).to_h
    started = WorkSeries.where(work_id: finished.keys).distinct.pluck(:series_id)
    ranked = Series.where(id: started).includes(:work_series).map do |series|
      read = series.work_series.map(&:work_id).select { |id| finished.key?(id) }
      rated = read.filter_map { |id| ratings[id]&.to_f }
      recency = read.filter_map { |id| finished[id] }.max
      score = (rated.any? ? rated.sum / rated.size : 3.0) + (recency && recency > @today - 365 ? 1 : 0)
      [ series, read, rated, score ]
    end.sort_by { |*, score| -score }

    ranked.lazy.filter_map do |series, read, rated, _|
      volumes = SeriesVolumes.for(series).entries.reject { |e| e.work&.literary_form == "nonfiction" }
      unread = volumes.reject { |e| e.work && read.include?(e.work.id) }
      next if unread.empty?

      Entry.new(series:, read: read.size, total: volumes.size, rating: (rated.sum / rated.size if rated.any?),
                next_entry: unread.find(&:position) || unread.first)
    end.first(limit)
  end
end

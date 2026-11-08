# A story series' page: every book in it in series order — those in the
# catalogue and, once the series is tied to ISFDB, every book ISFDB files
# there (SeriesVolumes) — with where each stands for Mark, a "Want it" for
# a book he doesn't have, and collecting the whole series (SeriesWant).
# Linked from the book page.
class SeriesController < ApplicationController
  before_action :set_series

  def show
    @volumes = SeriesVolumes.for(@series)
    @series_want = @series.series_want
  end

  def want_volume
    entry = SeriesVolumes.for(@series).entries.find { |e| e.title_id == Integer(params[:title_id]) }
    return redirect_to(series_path(@series), alert: "That book isn't in this series on ISFDB.") unless entry

    SeriesWants::Sync.want_volume(@series, entry)
    redirect_to series_path(@series), notice: "“#{entry.title}” is on your wishlist."
  end

  def collect
    SeriesWant.find_or_create_by!(series: @series)
    LineWantsJob.perform_later
    CatalogueEvent.record(kind: "series_collecting", summary: "Collecting the series #{@series.name}")
    redirect_to series_path(@series), notice: "Collecting this series — the books you don't have are being added to your wishlist."
  end

  def stop
    @series.series_want&.stop!
    redirect_to series_path(@series), notice: "Stopped collecting this series; the wants it added are gone."
  end

  # "Not this one": the book stays out, and a want the series made for it goes.
  def exclude
    series_want = @series.series_want or return redirect_to(series_path(@series))
    title_id = Integer(params[:title_id])
    series_want.update!(excluded_title_ids: series_want.excluded_title_ids | [ title_id ])
    series_want.wants.select { |w| w.work.work_identifiers.any? { |i| i.id_type == "isfdb_title" && i.value == title_id.to_s } }.each(&:retire!)
    redirect_to series_path(@series)
  end

  def include
    series_want = @series.series_want or return redirect_to(series_path(@series))
    series_want.update!(excluded_title_ids: series_want.excluded_title_ids - [ Integer(params[:title_id]) ])
    LineWantsJob.perform_later
    redirect_to series_path(@series)
  end

  private

  def set_series
    @series = Series.find(params[:id])
  end
end

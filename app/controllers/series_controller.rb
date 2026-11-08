# A story series' page: its books in series order, numbered, with where
# each stands for Mark. Linked from the book page.
class SeriesController < ApplicationController
  def show
    @series = Series.find(params[:id])
    @entries = @series.work_series.includes(work: WorksController::LIST_INCLUDES).to_a
                      .sort_by { |ws| [ ws.position || Float::INFINITY, ws.work.title.to_s.downcase ] }
  end
end

# A publisher's line (ISFDB publication series) — every number, and which
# Mark has — and collecting it (LineWant). Linked from an edition's line on
# the book page.
class LinesController < ApplicationController
  def show
    @line = PublicationLine.find(params[:id])
    @line_want = LineWant.find_by(pub_series_id: @line.id)
  end

  def collect
    line_want = LineWant.find_or_create_by!(pub_series_id: Integer(params[:id]))
    LineWantsJob.perform_later(line_want.id)
    CatalogueEvent.record(kind: "line_collecting", summary: "Collecting the line #{line_want.name || "ISFDB line #{line_want.pub_series_id}"}")
    redirect_to line_path(params[:id]), notice: "Collecting this line — its missing numbers are being added to your wants."
  end

  def stop
    LineWant.find_by(pub_series_id: Integer(params[:id]))&.stop!
    redirect_to line_path(params[:id]), notice: "Stopped collecting this line; the wants it added are gone."
  end

  # "Not this one": the number stays out, and a want the line made for it goes.
  def exclude
    line_want = LineWant.find_by!(pub_series_id: Integer(params[:id]))
    pub_id = Integer(params[:pub_id])
    line_want.update!(excluded_pub_ids: line_want.excluded_pub_ids | [ pub_id ])
    line_want.wants.select { |w| Array(w.printing_override_ids).include?(pub_id) }.each do |w|
      rest = w.printing_override_ids - [ pub_id ]
      rest.empty? ? w.retire! : w.update!(printing_override_ids: rest)
    end
    redirect_to line_path(params[:id])
  end

  def include
    line_want = LineWant.find_by!(pub_series_id: Integer(params[:id]))
    line_want.update!(excluded_pub_ids: line_want.excluded_pub_ids - [ Integer(params[:pub_id]) ])
    LineWantsJob.perform_later(line_want.id)
    redirect_to line_path(params[:id])
  end
end

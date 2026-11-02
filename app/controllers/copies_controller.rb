# Copies of an edition, from the book page (docs/CATALOG.md, build step 5):
# record one acquired, or what became of one (sold, given away, lost,
# replaced), or delete one added by mistake (CopyDeletion). Adding an edition the catalogue doesn't have yet is the add
# flow's job (build step 6).
class CopiesController < ApplicationController
  before_action :set_work

  def create
    edition = @work.editions.find(params.dig(:copy, :edition_id))
    copy = edition.copies.new(copy_params.merge(disposition: "owned"))
    if copy.save
      redirect_to work_path(@work), notice: "Copy added."
    else
      redirect_to work_path(@work), alert: copy.errors.full_messages.to_sentence
    end
  end

  def update
    copy = Copy.where(edition_id: @work.editions.select(:id)).find(params[:id])
    disposition = params.dig(:copy, :disposition).presence_in(Copy.dispositions.keys)
    if copy.update(copy_params.merge({ disposition: }.compact))
      redirect_to work_path(@work), notice: "Copy updated: #{Copy::DISPOSITION_LABELS.fetch(copy.disposition).downcase}."
    else
      redirect_to work_path(@work), alert: copy.errors.full_messages.to_sentence
    end
  end

  def destroy
    copy = Copy.where(edition_id: @work.editions.select(:id)).find(params[:id])
    edition_went = CopyDeletion.run(copy, work: @work)
    redirect_to work_path(@work), notice: edition_went ? "Copy deleted, and its edition with it." : "Copy deleted."
  end

  private

  def set_work = @work = Work.find(params[:work_id])

  def copy_params
    params.require(:copy).permit(:acquired_date, :acquired_price, :acquired_source, :condition, :notes)
  end
end

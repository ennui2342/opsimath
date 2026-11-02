# An edition on the book page (docs/CATALOG.md): what it is to Mark —
# owned, sold, not mine… with when / where he got it (EditionHolding) —
# or deleting one that was a mistake (EditionRemoval). Choosing a
# different printing for it is EditionChangesController.
class EditionsController < ApplicationController
  before_action :set_edition

  def holding
    EditionHolding.update(@edition, status: params[:status].to_s, details: details_params)
    redirect_to work_path(@work), notice: "Saved: #{EditionHolding::STATUSES.fetch(EditionHolding.status(@edition.reload)).downcase}."
  end

  def destroy
    move_to = @work.editions.find(params[:move_to]) unless params[:move_to].blank? || params[:move_to] == "delete"
    EditionRemoval.run(@edition, work: @work, move_to:)
    redirect_to work_path(@work), notice: "Edition deleted."
  rescue EditionRemoval::Refused => e
    redirect_to work_path(@work), alert: e.message
  end

  private

  def set_edition
    @work = Work.find(params[:work_id])
    @edition = @work.editions.find(params[:id])
  end

  def details_params = params.fetch(:details, {}).permit(*EditionHolding::DETAILS)
end

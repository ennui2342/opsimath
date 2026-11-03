# Wanting a book, from its book page (docs/CATALOG.md, build step 5): add
# one you already have to the wishlist (an upgrade hunt — bargain hunting
# then looks for the covers you want), or take a book off it. A wanted-only
# book's empty Work goes with its want (Want#retire!). The wishlist's own
# pages (/wishlist) are bargain hunting; this is the catalogue side.
class WantsController < ApplicationController
  before_action :set_work

  def create
    WantPrintingsJob.perform_later(@work.create_want!.id) unless @work.want
    redirect_to work_path(@work), notice: "Added to your wishlist."
  end

  def destroy
    want = @work.want
    return redirect_to(work_path(@work)) unless want

    want.retire!
    if Work.exists?(@work.id)
      redirect_to work_path(@work), notice: "Removed from your wishlist."
    else
      redirect_to works_path, notice: "Removed “#{@work.title}” from your wishlist."
    end
  end

  private

  def set_work = @work = Work.find(params[:work_id])
end

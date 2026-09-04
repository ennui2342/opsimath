# The book page — see docs/UI_PRINCIPLES.md principle 2: this screen's
# job is browsing/reference, not the review queue's throughput, so it
# stays a plain server-rendered page with no Turbo Streams involved.
class WorksController < ApplicationController
  def index
    @works = Work.order(:title)
  end

  def show
    @work = Work.includes(
      editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob }, { enrichment_records: { cover_image_attachment: :blob } } ]
    ).find(params[:id])
  end
end

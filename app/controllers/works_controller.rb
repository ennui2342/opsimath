# The book page — catalogue management since build step 5
# (docs/CATALOG.md): where a book's reading log, copies and wishlist state
# change. Still a plain server-rendered page: each action is a form that
# redirects back here, no Turbo Streams (docs/UI_PRINCIPLES.md principle 2
# — not a throughput screen).
class WorksController < ApplicationController
  FILTERS = %w[owned wanted reading read dnf].freeze

  # Every catalogued book with where it stands for Mark — owned, wanted,
  # reading, read, did not finish — filterable by that (since the wishlist
  # joined the catalogue, docs/CATALOG.md step 4, wanted-only books are
  # works too).
  def index
    @filter = params[:filter].presence_in(FILTERS)
    @works = Work.includes(:want, { work_contributors: :contributor }, :readings, editions: :copies).order(:title).to_a
    @statuses = @works.to_h { |w| [ w.id, w.statuses ] }
    @counts = FILTERS.to_h { |f| [ f, @statuses.count { |_, s| s.include?(f.to_sym) } ] }
    @works.select! { |w| @statuses[w.id].include?(@filter.to_sym) } if @filter
  end

  def show
    @work = Work.includes(
      :want, { work_contributors: :contributor }, { readings: :edition }, :reviews,
      editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob }, { enrichment_records: { cover_image_attachment: :blob } } ]
    ).find(params[:id])
    # Editions with a queued "which printing is yours?" — settled from the
    # edition picker (docs/CATALOG.md, build step 7).
    @printing_choices = PendingDecision.pending.where(kind: "enrichment_printing_choice")
                                       .where("payload->>'entity_type' = 'Edition'")
                                       .where("payload->>'entity_id' IN (?)", @work.editions.map { |e| e.id.to_s }.presence || [ "" ])
                                       .to_set { |d| d.payload["entity_id"].to_i }
  end
end

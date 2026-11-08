# The book page — catalogue management since build step 5
# (docs/CATALOG.md): where a book's reading log, copies and wishlist state
# change. Still a plain server-rendered page: each action is a form that
# redirects back here, no Turbo Streams (docs/UI_PRINCIPLES.md principle 2
# — not a throughput screen).
class WorksController < ApplicationController
  FILTERS = %w[owned wanted reading read dnf].freeze
  # What a book list needs to show titles, authors and statuses
  # (works/_book_list) without a query per row.
  LIST_INCLUDES = [ :want, { work_contributors: :contributor }, :readings, { editions: :copies } ].freeze

  # Every catalogued book with where it stands for Mark — owned, wanted,
  # reading, read, did not finish — filterable by that (since the wishlist
  # joined the catalogue, docs/CATALOG.md step 4, wanted-only books are
  # works too).
  #
  # `q` is the header search box (CatalogueSearch); one match goes straight
  # to its book page.
  def index
    @filter = params[:filter].presence_in(FILTERS)
    @query = params[:q].to_s.strip
    @works = Work.includes(:want, :series, { work_contributors: :contributor }, :readings, editions: [ :copies, :edition_identifiers ])
                 .order(:title).to_a
    @works = CatalogueSearch.filter(@works, @query) if @query.present?
    return redirect_to(work_path(@works.first)) if @query.present? && !@filter && @works.one?

    @statuses = @works.to_h { |w| [ w.id, w.statuses ] }
    @counts = FILTERS.to_h { |f| [ f, @statuses.count { |_, s| s.include?(f.to_sym) } ] }
    @works.select! { |w| @statuses[w.id].include?(@filter.to_sym) } if @filter
  end

  def show
    @work = Work.includes(
      :want, { work_contributors: :contributor }, { readings: :edition }, :reviews,
      editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob }, { enrichment_records: { cover_image_attachment: :blob } } ]
    ).find(params[:id])
    # Each edition's queued decisions (docs/CATALOG.md, build step 7 and
    # after): a "which printing is yours?" is settled from the edition
    # picker, anything else on the review screen, which returns here.
    @decisions = PendingDecision.pending.where("payload->>'entity_type' = 'Edition'")
                                .where("payload->>'entity_id' IN (?)", @work.editions.map { |e| e.id.to_s }.presence || [ "" ])
                                .order(:created_at).group_by { |d| d.payload["entity_id"].to_i }
  end
end

# The book page — catalogue management since build step 5
# (docs/CATALOG.md): where a book's reading log, copies and wishlist state
# change. Still a plain server-rendered page: each action is a form that
# redirects back here, no Turbo Streams (docs/UI_PRINCIPLES.md principle 2
# — not a throughput screen).
class WorksController < ApplicationController
  FILTERS = %w[owned wanted reading read dnf].freeze
  # Orders for the Books list; a filter has its own default (Reading: most
  # recently started first; Read: most recently finished).
  SORTS = { "title" => "Title", "author" => "Author", "added" => "Recently added", "started" => "Recently started",
            "finished" => "Recently finished" }.freeze
  DEFAULT_SORT = { "reading" => "started", "read" => "finished" }.freeze
  # What a book list needs to show titles, authors and statuses
  # (works/_book_list) without a query per row.
  LIST_INCLUDES = [ :want, { work_contributors: :contributor }, :readings, { editions: :copies } ].freeze
  # A list of books shown as edition cards (`size: :row` / `:tile`): each
  # edition's cover, copies, readings and identifiers, and the book's
  # printings for the edition's credited author.
  CARD_INCLUDES = [ :want, { work_contributors: :contributor }, :readings, :provider_editions,
                    { editions: [ :copies, :readings, :edition_identifiers, { cover_image_attachment: { blob: :variant_records } } ] } ].freeze

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
    @works = Work.includes(:want, :series, :work_alternate_titles, { work_contributors: :contributor }, :readings,
                           editions: [ :copies, :readings, :edition_identifiers, { cover_image_attachment: { blob: :variant_records } } ])
                 .order(:title).to_a
    @works = CatalogueSearch.filter(@works, @query) if @query.present?
    return redirect_to(work_path(@works.first)) if @query.present? && !@filter && @works.one?

    @statuses = @works.to_h { |w| [ w.id, w.statuses ] }
    @counts = FILTERS.to_h { |f| [ f, @statuses.count { |_, s| s.include?(f.to_sym) } ] }
    @works.select! { |w| @statuses[w.id].include?(@filter.to_sym) } if @filter
    @sort = params[:sort].presence_in(SORTS.keys) || DEFAULT_SORT.fetch(@filter, "title")
    @works = sorted(@works, @sort)
  end

  def show
    @work = Work.includes(
      :want, { work_contributors: :contributor }, { readings: [ :reviews, { edition: { cover_image_attachment: :blob } } ] }, :reviews,
      :provider_editions,
      editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob }, { enrichment_records: { cover_image_attachment: :blob } } ]
    ).find(params[:id])
    # The lists it's on (docs/LISTS.md), for its badges.
    @list_entries = BookListEntry.includes(:book_list).where(isfdb_title_id: @work.work_identifiers.select { |i| i.id_type == "isfdb_title" }.map { |i| i.value.to_i })
                                 .sort_by { |e| [ e.winner? ? 0 : 1, e.year || 0 ] }
    # Each edition's queued decisions (docs/CATALOG.md, build step 7 and
    # after): a "which printing is yours?" is settled from the edition
    # picker, anything else on the review screen, which returns here.
    @decisions = PendingDecision.pending.where("payload->>'entity_type' = 'Edition'")
                                .where("payload->>'entity_id' IN (?)", @work.editions.map { |e| e.id.to_s }.presence || [ "" ])
                                .order(:created_at).group_by { |d| d.payload["entity_id"].to_i }
  end

  # Removing a book entirely — a duplicate or a mistake (WorkRemoval).
  def destroy
    work = Work.find(params[:id])
    move_to = Work.find(params[:move_to]) if params[:move_to].present? && params[:move_to] != "delete"
    WorkRemoval.run(work, move_to:)
    redirect_to(move_to ? work_path(move_to) : works_path, notice: "Removed “#{work.title}” from the catalogue.")
  rescue WorkRemoval::Refused => e
    redirect_to work_path(work), alert: e.message
  end

  # The list in `sort` order; books without the date sort last.
  def sorted(works, sort)
    far = Date.new(1, 1, 1)
    case sort
    when "author" then works.sort_by { |w| [ w.authors.first&.sort_name.presence || w.authors.first&.name.to_s, w.title.downcase ] }
    when "added" then works.sort_by { |w| -w.created_at.to_i }
    when "started" then works.sort_by { |w| [ -(w.readings.filter_map(&:date_started).max || far).jd, w.title.downcase ] }
    when "finished" then works.sort_by { |w| [ -(w.readings.select(&:completed?).filter_map(&:date_finished).max || far).jd, w.title.downcase ] }
    else works.sort_by { |w| w.title.downcase }
    end
  end
end

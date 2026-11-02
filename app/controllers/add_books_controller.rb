# Adding a book (docs/CATALOG.md, build step 6) — at the desk, after a
# day's purchases: find the work, choose the edition by cover and
# publisher, say what it is to you. Also how a wanted book is got: its
# page links here with work_id.
#
# What a page offers (a search result, an edition card) travels to the
# next request signed, so saving needs no second provider lookup — and a
# pre-ISBN printing couldn't be looked up again anyway.
class AddBooksController < ApplicationController
  TOKEN_TTL = 1.day

  def new
    @query = params[:q].to_s.strip
    @results = @query.present? ? AddBook::Search.run(@query) : []
  end

  def editions
    @work = Work.find(params[:work_id]) if params[:work_id]
    @found = read(params[:found]) unless @work
    return redirect_to(add_book_path, alert: "That search result has expired — search again.") unless @work || @found

    @title = @work&.title || @found["title"]
    @cards, @hidden = AddBook::EditionCards.build(provider_editions, all_languages: params[:all_languages].present?)
  end

  def create
    work = Work.find(params[:work_id]) if params[:work_id].present?
    found = read(params[:found]) unless work
    return redirect_to(add_book_path, alert: "That search result has expired — search again.") unless work || found

    if params[:intent] == "want"
      want = AddBook::Create.want(work:, found:)
      return redirect_to work_path(want.work), notice: "Added to your wishlist."
    end

    card = read(params[:card])
    return redirect_back_or_to(add_book_path, alert: "Choose an edition.") unless card

    work, = AddBook::Create.edition(work:, found:, card:, own: params[:own] == "1", reading: reading_params)
    redirect_to work_path(work), notice: "Added to your catalogue."
  end

  helper_method :sign

  def sign(payload) = verifier.generate(payload, expires_in: TOKEN_TTL)

  private

  def verifier = Rails.application.message_verifier(:add_book)

  def read(token) = token.present? ? verifier.verified(token) : nil

  # The editions to choose between: a catalogued work's known editions
  # (no network) — fetched live only if it has none yet — or a search
  # result's, fetched from each provider.
  def provider_editions
    if @work && @work.provider_editions.any?
      AddBook::EditionCards.from_provider_editions(@work.provider_editions)
    else
      fetch_live(@work ? works_for(@work) : @found["provider_works"])
    end
  end

  # A catalogued work as provider works: ISFDB by the ISBNs it's known by
  # (its editions' and its want's), Open Library by each stored work id —
  # it can hold several for one book (its duplicate works).
  def works_for(work)
    isbns = work.editions.flat_map(&:edition_identifiers).select { |i| i.id_type.start_with?("isbn") }.map(&:value) +
            Array(work.want&.seed_isbns)
    ol_ids = work.work_identifiers.select { |i| i.id_type == "openlibrary_work" }.map(&:value)
    [ { "provider" => "isfdb", "isbns" => isbns } ] + ol_ids.map { |id| { "provider" => "openlibrary", "id" => id } }
  end

  def fetch_live(provider_works)
    Array(provider_works).flat_map do |pw|
      case pw["provider"]
      when "isfdb"
        isbn = Array(pw["isbns"]).first
        isbn ? Providers::Isfdb.new.editions_for_isbn(isbn) : Array(pw["editions"]).map { |e| Providers::Edition.new(**e.symbolize_keys) }
      when "openlibrary"
        pw["id"].present? ? Providers::OpenLibrary.new.editions(pw["id"]) : []
      else []
      end
    rescue StandardError => e
      Rails.logger.warn("add book: #{pw["provider"]} editions — #{e.class}: #{e.message}")
      []
    end
  end

  def reading_params
    case params[:reading_status]
    when "reading" then { status: "reading", date_started: params[:date_started].presence || Date.current, source: "owned_copy" }
    when "read" then { status: "completed", date_finished: params[:date_finished].presence || Date.current,
                       rating: params[:rating].presence, source: "owned_copy" }
    end
  end
end

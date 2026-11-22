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
    search = AddBook::Search.new
    @results = @query.present? ? search.run(@query) : []
    @missed = search.missed
  end

  def editions
    @work = Work.find(params[:work_id]) if params[:work_id]
    @found = read(params[:found]) unless @work
    return redirect_to(add_book_path, alert: "That search result has expired — search again.") unless @work || @found

    @title = @work&.title || @found["title"]
    @missed = []
    editions = @work ? AddBook::EditionSource.for_work(@work) : AddBook::EditionSource.for_found(@found, missed: @missed)
    @cards, @hidden = AddBook::EditionCards.build(editions, all_languages: params[:all_languages].present?)
    # Searched by ISBN: its printings first, marked — several can share
    # one, among dozens of cards (Mythago Wood's 0586065857: five
    # printings in 30 cards, 2026-11-22).
    @isbn = Isbn.normalize(params[:isbn].to_s)&.then { |i| Isbn.to_13(i) }
    @cards = @cards.sort_by.with_index { |card, i| [ your_isbn?(card) ? 0 : 1, i ] } if @isbn
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

    holding = params[:holding].to_s
    replaces = work&.editions&.find_by(id: holding.delete_prefix("replaces:")) if holding.start_with?("replaces:")
    work, = AddBook::Create.edition(work:, found:, card:, own: holding != "not_mine", replaces:, reading: reading_params)
    redirect_to work_path(work), notice: replaces ? "Added; the edition it replaces is marked replaced." : "Added to your catalogue."
  end

  helper_method :sign

  def sign(payload) = verifier.generate(payload, expires_in: TOKEN_TTL)

  private

  # A card holding the ISBN searched for.
  helper_method def your_isbn?(card) = @isbn.present? && card.isbns.include?(@isbn)

  def verifier = Rails.application.message_verifier(:add_book)

  def read(token) = token.present? ? verifier.verified(token) : nil

  # Where a read came from: their own book, else the "Not mine — read
  # from a …" choice.
  def reading_params
    source = params[:holding] == "not_mine" ? params[:read_from].presence_in(%w[library borrowed other]) || "other" : "owned_copy"
    case params[:reading_status]
    when "reading" then { status: "reading", date_started: params[:date_started].presence || Date.current, source: }
    when "read" then { status: "completed", date_finished: params[:date_finished].presence || Date.current,
                       rating: params[:rating].presence, source: }
    end
  end
end

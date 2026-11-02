# "Not this edition" (docs/CATALOG.md, build step 7): re-point an edition
# on file at the printing Mark actually has, chosen from the same cards as
# adding a book. Also where a queued printing choice is settled — the
# book page links here for one. See EditionChange.
class EditionChangesController < ApplicationController
  before_action :set_edition

  def edit
    editions = AddBook::EditionSource.for_work(@work) + decision_candidates
    @cards, @hidden = AddBook::EditionCards.build(editions.uniq { |e| [ e.provider, e.id ] }, all_languages: params[:all_languages].present?)
    @isbn = @edition.edition_identifiers.find { |i| i.id_type == "isbn13" }&.value
    @current = @edition.edition_identifiers.select { |i| EditionChange::PROVIDERS.include?(i.id_type) }.map { |i| [ i.id_type, i.value ] }
    @cards = @cards.sort_by.with_index { |card, i| [ [ "Yours now", "Same ISBN", nil ].index(notes_for(card).first), i ] }
    @choice_pending = EditionChange.decisions(@edition).any? { |d| d.kind == "enrichment_printing_choice" }
    @other_editions = @work.editions.includes(:copies, :readings).reject { |e| e == @edition }.sort_by(&:id)
    @shared = @edition.works.where.not(id: @work.id).to_a
  end

  def update
    card = params[:card].present? && verifier.verified(params[:card])
    return redirect_to(edit_work_edition_change_path(@work, @edition), alert: "Choose an edition.") unless card

    EditionChange.run(@edition, card)
    redirect_to work_path(@work), notice: "Edition changed to #{@edition.reload.publisher || 'the one you chose'}."
  end

  # Remove the edition (EditionRemoval): its copies and readings move to
  # `move_to`, or go with it when that's "delete".
  def destroy
    move_to = @work.editions.find(params[:move_to]) unless params[:move_to].blank? || params[:move_to] == "delete"
    EditionRemoval.run(@edition, work: @work, move_to:)
    redirect_to work_path(@work), notice: "Edition removed."
  rescue EditionRemoval::Refused => e
    redirect_to edit_work_edition_change_path(@work, @edition), alert: e.message
  end

  helper_method :sign, :notes_for

  def sign(payload) = verifier.generate(payload, expires_in: AddBooksController::TOKEN_TTL)

  def notes_for(card)
    notes = []
    notes << "Yours now" if card.editions.any? { |e| @current.include?([ e.provider, e.id.to_s ]) }
    notes << "Same ISBN" if @isbn && card.isbns.include?(@isbn)
    notes
  end

  private

  def verifier = Rails.application.message_verifier(:edition_change)

  def set_edition
    @work = Work.find(params[:work_id])
    @edition = @work.editions.find(params[:id])
  end

  # A queued printing choice's candidates — the ISFDB printings under this
  # edition's ISBN — whether or not the work's known editions have them yet.
  def decision_candidates
    isfdb = Providers::Isfdb.new
    EditionChange.decisions(@edition).select { |d| d.kind == "enrichment_printing_choice" }
                 .flat_map { |d| Array(d.payload["candidates"]) }.filter_map { |raw| isfdb.edition_from(raw) }
  end
end

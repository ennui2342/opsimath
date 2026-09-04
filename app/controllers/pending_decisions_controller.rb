# The review queue — see docs/UI_PRINCIPLES.md principles 2-4: this
# screen's job is fast, repeated decisions, so accept/reject respond
# with a Turbo Stream swapping straight to the next pending decision
# in place, not a full page redirect back to the index.
class PendingDecisionsController < ApplicationController
  before_action :set_pending_decision, only: [ :show, :accept, :reject, :resolve ]

  def index
    @kind = params[:kind].presence
    @kind_counts = PendingDecision.pending.group(:kind).count
    scope = PendingDecision.pending.order(:created_at)
    scope = scope.where(kind: @kind) if @kind
    @pending_decisions = scope
  end

  def show
    @kind = params[:kind].presence
  end

  def accept
    Enrichment::PendingDecisionResolver.accept(@pending_decision, selected_fields: params[:fields], pub_id: params[:pub_id])
    advance
  end

  def reject
    Enrichment::PendingDecisionResolver.reject(@pending_decision)
    advance
  end

  # edition_reconciliation's own resolution vocabulary
  # (relink/change_edition/add_edition/unowned_read/rejected) doesn't fit
  # accept/reject's binary, so it gets its own verb — the one place this
  # queue's shared accept/reject/resolve trio isn't uniform across every
  # kind, same as accept already isn't (selected_fields vs. pub_id).
  def resolve
    @kind = params[:kind].presence
    Goodreads::EditionReconciliationResolver.resolve(
      @pending_decision, resolution: params[:resolution],
      target_edition_id: params[:target_edition_id].presence, source: params[:source].presence
    )
    advance
  rescue Goodreads::EditionReconciliationResolver::InvalidResolution => e
    redirect_to pending_decision_path(@pending_decision, kind: @kind), alert: e.message
  end

  private

  def set_pending_decision
    @pending_decision = PendingDecision.find(params[:id])
  end

  def advance
    @kind = params[:kind].presence
    next_scope = PendingDecision.pending.order(:created_at)
    next_scope = next_scope.where(kind: @kind) if @kind
    @next_decision = next_scope.first

    respond_to do |format|
      format.turbo_stream { render "advance" }
      format.html do
        if @next_decision
          redirect_to pending_decision_path(@next_decision, kind: @kind)
        else
          redirect_to pending_decisions_path(kind: @kind), notice: "All caught up!"
        end
      end
    end
  end
end

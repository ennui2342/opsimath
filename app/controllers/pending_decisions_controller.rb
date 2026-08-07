# The review queue — see docs/UI_PRINCIPLES.md principles 2-4: this
# screen's job is fast, repeated decisions, so accept/reject respond
# with a Turbo Stream swapping straight to the next pending decision
# in place, not a full page redirect back to the index.
class PendingDecisionsController < ApplicationController
  before_action :set_pending_decision, only: [ :show, :accept, :reject ]

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
    Enrichment::PendingDecisionResolver.accept(@pending_decision, selected_fields: params[:fields])
    advance
  end

  def reject
    Enrichment::PendingDecisionResolver.reject(@pending_decision)
    advance
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

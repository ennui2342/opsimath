# The review queue — see docs/UI_PRINCIPLES.md principles 2-4: this
# screen's job is fast, repeated decisions, so accept/reject respond
# with a Turbo Stream swapping straight to the next pending decision
# in place, not a full page redirect back to the index.
#
# Default order is alphabetical by #display_title (Mark, 2026-09-04) —
# not a real column (it's derived per-kind from payload/entity, see
# PendingDecision#display_title), so both the index and #advance sort in
# Ruby rather than in SQL. `[title, id]` as the sort key rather than title
# alone for the same reason `order(:created_at, ...)` used to carry `:id`
# — a stable tiebreaker for the rare exact-title match. Fine at today's
# scale (low hundreds of pending decisions, one extra #entity lookup per
# row already memoized by #display_title itself) — revisit if this queue
# ever grows enough to need pagination.
class PendingDecisionsController < ApplicationController
  before_action :set_pending_decision, only: [ :show, :accept, :reject, :resolve ]

  def index
    @kind = params[:kind].presence
    @kind_counts = PendingDecision.pending.group(:kind).count
    scope = PendingDecision.pending
    scope = scope.where(kind: @kind) if @kind
    @pending_decisions = sort_by_title(scope)
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
    next_scope = PendingDecision.pending
    next_scope = next_scope.where(kind: @kind) if @kind
    @next_decision = sort_by_title(next_scope).first

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

  def sort_by_title(scope)
    scope.to_a.sort_by { |pd| [ pd.display_title.downcase, pd.id ] }
  end
end

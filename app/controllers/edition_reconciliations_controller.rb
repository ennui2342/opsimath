# The second review queue (see docs/DATA_MODEL.md `EditionReconciliation`).
# Same fast-triage shape as PendingDecisionsController: `resolve` swaps
# straight to the next pending item via Turbo Stream rather than
# redirecting to the index.
class EditionReconciliationsController < ApplicationController
  before_action :set_reconciliation, only: [ :show, :resolve ]

  def index
    @reconciliations = EditionReconciliation.pending.order(:created_at)
  end

  def show
  end

  def resolve
    Goodreads::EditionReconciliationResolver.resolve(
      @reconciliation,
      resolution: params[:resolution],
      target_edition_id: params[:target_edition_id].presence,
      source: params[:source].presence
    )
    advance
  rescue Goodreads::EditionReconciliationResolver::InvalidResolution => e
    redirect_to edition_reconciliation_path(@reconciliation), alert: e.message
  end

  private

  def set_reconciliation
    @reconciliation = EditionReconciliation.find(params[:id])
  end

  def advance
    @next_reconciliation = EditionReconciliation.pending.order(:created_at).first

    respond_to do |format|
      format.turbo_stream { render "advance" }
      format.html do
        if @next_reconciliation
          redirect_to edition_reconciliation_path(@next_reconciliation)
        else
          redirect_to edition_reconciliations_path, notice: "All caught up!"
        end
      end
    end
  end
end

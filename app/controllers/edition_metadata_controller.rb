# The on-demand "reconcile this edition against its known sources" screen
# — reached from the cog on Ui::EditionCardComponent (book page), and the
# quick right-click cover-swap modal (a single pick submitted straight to
# #update). Unlike PendingDecisionsController this isn't a queue: nothing
# is "resolved," there's always exactly one edition, and the page just
# reflects whatever's true right now — a plain Turbo-Drive page per
# docs/UI_PRINCIPLES.md principle 4 (no throughput need here).
class EditionMetadataController < ApplicationController
  before_action :set_edition

  def show
    @cards = Enrichment::EditionMetadataCards.build(@edition)
  end

  def update
    applied = Enrichment::EditionMetadataResolver.apply(@edition, picks: params[:field_picks])
    redirect_to (@edition.works.first ? work_path(@edition.works.first) : root_path), notice: update_notice(applied)
  rescue Enrichment::EditionMetadataResolver::InvalidPick => e
    redirect_to edition_metadata_path(@edition), alert: e.message
  end

  private

  def set_edition
    @edition = Edition.find(params[:edition_id])
  end

  def update_notice(applied)
    return "Nothing selected — edition unchanged." if applied.empty?

    "Updated #{applied.map(&:humanize).join(", ")}."
  end
end

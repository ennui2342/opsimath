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
    @work = @edition.works.first
    @title_choices = title_choices if @work
  end

  # The book's title from the cog: one of the sources' titles or Mark's
  # own — his either way ("manual"), so nothing automatic changes it after.
  def title
    work = @edition.works.first or return redirect_to(root_path)
    chosen = params[:custom_title].to_s.strip.presence || params[:title].to_s.strip.presence
    return redirect_to(edition_metadata_path(@edition), alert: "No title given.") unless chosen

    TitleCleanup.retitle(work, chosen, source: "manual")
    redirect_to work_path(work), notice: "Title set: “#{chosen}”."
  end

  def update
    applied = Enrichment::EditionMetadataResolver.apply(@edition, picks: params[:field_picks])
    redirect_to (@edition.works.first ? work_path(@edition.works.first) : root_path), notice: update_notice(applied)
  rescue Enrichment::EditionMetadataResolver::InvalidPick => e
    redirect_to edition_metadata_path(@edition), alert: e.message
  end

  private

  # [title, where from] — the book's own, then each source's for this
  # edition (its ISFDB printing's, Open Library's, Goodreads'), distinct.
  def title_choices
    from_records = @edition.enrichment_records.filter_map { |r| [ r.raw_payload&.dig("title").presence, r.provider ] }.select(&:first)
    printing = TitleCleanup.isfdb_title(@work)
    ([ [ @work.title, "current" ] ] + (printing ? [ [ printing, "isfdb" ] ] : []) + from_records)
      .uniq(&:first)
  end

  def set_edition
    @edition = Edition.find(params[:edition_id])
  end

  def update_notice(applied)
    return "Nothing selected — edition unchanged." if applied.empty?

    "Updated #{applied.map(&:humanize).join(", ")}."
  end
end

# The Phase 2 ongoing sync job from docs/INTEGRATIONS.md — polls all 5
# Goodreads shelf RSS feeds and applies whatever changed since the last
# run. See Goodreads::Syncer for the orchestration and diffing logic.
#
# Also the one place this whole feature talks to Notifications — kept out
# of Syncer/ShelfSync deliberately, so those stay pure and testable
# without a Discord round-trip. Two things worth being deliberate about:
#
# - A freshly auto-created Edition gets ISFDB enrichment triggered right
#   here, scoped to just that one Edition — NOT a call into the existing
#   bulk IsfdbEnrichmentJob/`isfdb:enrich_editions` rake task, which stays
#   completely untouched and silent. Wiring notifications into the bulk
#   job would flood Discord with hundreds of messages on a full-library
#   run; this way "notify when the Goodreads updater's own activity needs
#   review" and "no flood from bulk import" fall out of the same design
#   without a special flag.
# - A notification failure must never fail the sync itself — see
#   Notifications.notify's own rescue for that; nothing here needs to
#   duplicate it.
class GoodreadsSyncJob < ApplicationJob
  queue_as :default

  # One book-level notification per touched shelf item — not just a
  # genuinely new book — so every sync run is visible, not just the
  # subset that happened to auto-create something (Mark's own ask: "so I
  # can see how the library is being updated"). "Added to catalog"
  # always wins over the shelf-specific wording when this is the item's
  # first appearance in the library at all (a Work/Edition/Copy didn't
  # exist before this run) — that's the more significant fact regardless
  # of which shelf triggered it. wishlist is the one exception: it never
  # creates a Work/Edition/Copy (see ShelfSync#wishlist), so "added to
  # catalog" would be a lie even when touched.created is true.
  SHELF_TITLES = {
    "wishlist" => "Added to wishlist",
    "to-read" => "Marked to-read",
    "currently-reading" => "Started reading",
    "read" => "Finished reading",
    "did-not-finish" => "Did not finish"
  }.freeze

  def perform(rss_client: Goodreads::RssClient.new)
    result = run_sync(rss_client)
    result[:touched].each { |t| process_touched(t) }
    notify_summary(result[:counts])
    result[:counts]
  end

  private

  def run_sync(rss_client)
    Goodreads::Syncer.sync(rss_client: rss_client)
  rescue StandardError => e
    Notifications.notify(Notifications::Event.new(
      kind: :sync_error, level: :error, title: "Goodreads sync failed",
      fields: { "error" => "#{e.class}: #{e.message}" }
    ))
    raise
  end

  def process_touched(touched)
    JobItem.create!(run_id: job_id, entity: touched.entity, status: "success", message: "#{touched.shelf}: #{touched.goodreads_book_id}")

    if touched.entity.is_a?(PendingDecision)
      notify_pending_decision(touched.entity, touched)
      return
    end

    # touched (Syncer's "no matching GoodreadsSyncState, so this needs
    # processing" signal) is not the same thing as changed (ShelfSync's
    # "a real database write happened as a result" signal) — a re-touch
    # of an already-fully-known item (the common case right after a
    # GoodreadsSyncState reset) is touched but not changed. Real bug
    # found live in production (2026-08-08): notifying on touched alone
    # reported "Added to wishlist"/"Started reading" for books that had
    # been there for ages, with zero actual writes behind them.
    return unless touched.changed

    notify_shelf_update(touched)
    enrich_new_edition(touched.edition) if touched.created && touched.edition
  end

  def notify_shelf_update(touched)
    catalog_new = touched.created && touched.shelf != "wishlist"
    title = catalog_new ? "Added to catalog" : SHELF_TITLES.fetch(touched.shelf)

    Notifications.notify(Notifications::Event.new(
      kind: catalog_new ? :auto_created : :shelf_update, level: :info,
      title: "#{title}: #{touched.title}",
      fields: { "shelf" => touched.shelf, "goodreads_book_id" => touched.goodreads_book_id }
    ))
  end

  def notify_pending_decision(pending_decision, touched)
    Notifications.notify(Notifications::Event.new(
      kind: :pending_decision, level: :warn, title: "Needs review: #{pending_decision.kind} — #{touched.title}",
      fields: { "shelf" => touched.shelf, "goodreads_book_id" => touched.goodreads_book_id, "pending_decision_id" => pending_decision.id }
    ))
  end

  def enrich_new_edition(edition)
    result = Enrichment::IsfdbEditionEnricher.enrich(edition)
    return unless result.status == :success

    # A brand-new Edition has no prior history, so any PendingDecision
    # found here was necessarily just raised by this exact call.
    PendingDecision.where(status: "pending")
                   .where("payload @> ?", { "entity_type" => "Edition", "entity_id" => edition.id }.to_json)
                   .find_each { |pending_decision| notify_enrichment_conflict(pending_decision, edition) }
  end

  # The bare kind ("enrichment_field_conflict"/"enrichment_edition_mismatch")
  # told you nothing actionable on its own — no title, no idea what's
  # actually in dispute. PendingDecision#field_diffs derives the real
  # current-vs-proposed comparison live (payload itself is just a thin
  # pointer — see Enrichment::FieldApplier.find_or_create_conflict) so
  # the Discord message alone is enough to judge whether it's worth
  # opening the console for.
  def notify_enrichment_conflict(pending_decision, edition)
    title = edition.works.map(&:title).join(", ").presence || "Edition #{edition.id}"

    Notifications.notify(Notifications::Event.new(
      kind: :pending_decision, level: :warn,
      title: "ISFDB enrichment needs review: #{pending_decision.kind} — #{title}",
      fields: { "title" => title, "pending_decision_id" => pending_decision.id }.merge(conflict_summary(pending_decision))
    ))
  end

  def conflict_summary(pending_decision)
    pending_decision.field_diffs.each_with_object({}) do |diff, summary|
      summary[diff[:field]] = "#{diff[:current] || "(blank)"} → #{diff[:proposed]}"
    end
  end

  # A no-op run (nothing new on any shelf, the overwhelmingly common
  # case once caught up) has already been silent on Discord for anything
  # that matters — sending a summary anyway every single hour is pure
  # noise, not a useful "yes it's alive" heartbeat.
  def notify_summary(counts)
    return unless counts.synced.positive?

    Notifications.notify(Notifications::Event.new(
      kind: :sync_summary, level: :info, title: "Goodreads sync complete",
      fields: { "synced" => counts.synced, "unchanged" => counts.unchanged }
    ))
  end
end

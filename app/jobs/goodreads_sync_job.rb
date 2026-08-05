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
    elsif touched.created && touched.edition
      notify_auto_created(touched)
      enrich_new_edition(touched.edition)
    end
  end

  def notify_auto_created(touched)
    Notifications.notify(Notifications::Event.new(
      kind: :auto_created, level: :info, title: "Added to catalog: #{touched.title}",
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
                   .find_each do |pending_decision|
      Notifications.notify(Notifications::Event.new(
        kind: :pending_decision, level: :warn, title: "ISFDB enrichment needs review: #{pending_decision.kind}",
        fields: { "edition_id" => edition.id, "pending_decision_id" => pending_decision.id }
      ))
    end
  end

  def notify_summary(counts)
    Notifications.notify(Notifications::Event.new(
      kind: :sync_summary, level: :info, title: "Goodreads sync complete",
      fields: { "synced" => counts.synced, "unchanged" => counts.unchanged }
    ))
  end
end

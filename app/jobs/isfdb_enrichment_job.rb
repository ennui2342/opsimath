# The batch enrichment job from docs/INTEGRATIONS.md's "Enrichment at
# import time" section — one run over every Edition with a real ISBN
# that hasn't been tried against isfdb-adapter yet. Edition-scoped, not
# Work-scoped — see Enrichment::IsfdbEditionEnricher for why.
class IsfdbEnrichmentJob < ApplicationJob
  queue_as :default

  Counts = Struct.new(:success, :failed, :skipped, keyword_init: true) do
    def to_s
      "success=#{success} failed=#{failed} skipped=#{skipped}"
    end
  end

  # force: true re-fetches every ISBN-bearing edition, including ones
  # that already have an isfdb EnrichmentRecord — for a change to what
  # isfdb-adapter returns or how it's applied (a new field like
  # cover_artist, CoverApplier's `authoritative:` cover trust) that only
  # actually reaches an edition on its next real fetch. Off by default:
  # the ordinary case only wants to pick up editions no one's tried yet,
  # not re-hit isfdb-adapter for the whole library every run. See
  # `isfdb:reenrich_editions` in lib/tasks/isfdb.rake.
  def perform(force: false)
    client = Isfdb::Client.new
    counts = Counts.new(success: 0, failed: 0, skipped: 0)

    editions_to_enrich(force:).find_each do |edition|
      result = Enrichment::IsfdbEditionEnricher.enrich(edition, client: client)
      status = job_item_status(result.status)
      JobItem.create!(run_id: job_id, entity: edition, status: status, message: result.message)
      counts[status.to_sym] += 1
    end

    counts
  end

  private

  def editions_to_enrich(force:)
    scope = Edition.joins(:edition_identifiers).where(edition_identifiers: { id_type: %w[isbn13 isbn10] }).distinct
    return scope if force

    # Not yet attempted against isfdb-adapter — re-running the job only
    # picks up editions with no prior isfdb EnrichmentRecord, rather than
    # re-fetching the whole library every time.
    scope.where.not(id: EnrichmentRecord.where(entity_type: "Edition", provider: "isfdb").select(:entity_id))
  end

  def job_item_status(enricher_status)
    case enricher_status
    when :success then "success"
    when :failed then "failed"
    else "skipped"
    end
  end
end

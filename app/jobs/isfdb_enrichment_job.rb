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

  def perform
    client = Isfdb::Client.new
    counts = Counts.new(success: 0, failed: 0, skipped: 0)

    editions_to_enrich.find_each do |edition|
      result = Enrichment::IsfdbEditionEnricher.enrich(edition, client: client)
      status = job_item_status(result.status)
      JobItem.create!(run_id: job_id, entity: edition, status: status, message: result.message)
      counts[status.to_sym] += 1
    end

    counts
  end

  private

  # Not yet attempted against isfdb-adapter — re-running the job only
  # picks up editions with no prior isfdb EnrichmentRecord, rather than
  # re-fetching the whole library every time.
  def editions_to_enrich
    Edition.joins(:edition_identifiers)
           .where(edition_identifiers: { id_type: %w[isbn13 isbn10] })
           .where.not(id: EnrichmentRecord.where(entity_type: "Edition", provider: "isfdb").select(:entity_id))
           .distinct
  end

  def job_item_status(enricher_status)
    case enricher_status
    when :success then "success"
    when :failed then "failed"
    else "skipped"
    end
  end
end

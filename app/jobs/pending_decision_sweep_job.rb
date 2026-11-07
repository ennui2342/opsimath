# Nightly backstop for PendingDecisionSweep: closes any pending decision
# about an edition that no longer has anything to decide.
class PendingDecisionSweepJob < ApplicationJob
  queue_as :default

  def perform
    counts = PendingDecisionSweep.all
    return if counts.empty?

    Rails.logger.info("pending decision sweep: #{counts.inspect}")
    CatalogueEvent.record(kind: "decisions_closed", origin: "sweep", details: counts,
                          summary: "Closed #{counts.values.sum} review #{'decision'.pluralize(counts.values.sum)} with nothing left to decide")
  end
end

# Nightly backstop for PendingDecisionSweep: closes any pending decision
# about an edition that no longer has anything to decide.
class PendingDecisionSweepJob < ApplicationJob
  queue_as :default

  def perform
    counts = PendingDecisionSweep.all
    Rails.logger.info("pending decision sweep: #{counts.inspect}") if counts.any?
  end
end

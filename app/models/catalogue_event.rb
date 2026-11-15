# One readable line about something that changed in the catalogue — "Added
# The Days of Glory: Five Star (UK) 1973, owned", "3 new printings of The
# Birthgrave" — posted to Discord's #catalogue by CatalogueReport. Recorded
# explicitly where the change happens (paper_trail keeps only each record's
# previous state, not what changed, so it can't be read back as a story).
#
# `origin` is "web" for Mark's edits, else the job that made the change.
# A change made by a command run by hand — a one-off correction from the
# console, a runner or a rake task, not a background job — is tagged
# details["by"] = "correction" and posted within minutes, with Mark's
# edits, rather than in the morning digest as if the nightly run had done
# it (Mark, 2026-11-15). Recording never breaks the action it describes.
class CatalogueEvent < ApplicationRecord
  belongs_to :work, optional: true

  scope :unreported, -> { where(reported_at: nil) }
  scope :from_web, -> { where(origin: "web") }
  scope :corrections, -> { where("details->>'by' = 'correction'") }
  scope :from_jobs, -> { where.not(origin: "web").where("coalesce(details->>'by', '') <> 'correction'") }

  def self.record(kind:, summary:, work: nil, details: {}, origin: nil)
    details = details.merge("by" => "correction") if correction?
    create!(kind:, summary:, work:, details:, origin: origin || (Current.user ? "web" : "job"))
  rescue StandardError => e
    Rails.logger.warn("catalogue event not recorded (#{kind}): #{e.class}: #{e.message}")
    nil
  end

  # Run by hand: not a background job, not Mark on the web — a rails
  # runner, the console, or a rake task.
  def self.correction?
    return false if Current.job || Current.user

    defined?(Rails::Command::RunnerCommand) || defined?(Rails::Console) ||
      (defined?(Rake) && Rake.respond_to?(:application) && Rake.application.top_level_tasks.any?) ? true : false
  end

  # "The Days of Glory" / "Five Star (UK) 1973" — the phrases events use.
  def self.title(work) = work&.title.presence || "a book"

  def self.edition_label(edition)
    [ edition.publisher.presence || "edition", edition.publish_date.to_s[0, 4].presence ].compact.join(" ")
  end
end

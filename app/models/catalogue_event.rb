# One readable line about something that changed in the catalogue — "Added
# The Days of Glory: Five Star (UK) 1973, owned", "3 new printings of The
# Birthgrave" — posted to Discord's #catalogue by CatalogueReport. Recorded
# explicitly where the change happens (paper_trail keeps only each record's
# previous state, not what changed, so it can't be read back as a story).
#
# `origin` is "web" for Mark's edits, else the job that made the change.
# Recording never breaks the action it describes.
class CatalogueEvent < ApplicationRecord
  belongs_to :work, optional: true

  scope :unreported, -> { where(reported_at: nil) }
  scope :from_web, -> { where(origin: "web") }
  scope :from_jobs, -> { where.not(origin: "web") }

  def self.record(kind:, summary:, work: nil, details: {}, origin: nil)
    create!(kind:, summary:, work:, details:, origin: origin || (Current.user ? "web" : "job"))
  rescue StandardError => e
    Rails.logger.warn("catalogue event not recorded (#{kind}): #{e.class}: #{e.message}")
    nil
  end

  # "The Days of Glory" / "Five Star (UK) 1973" — the phrases events use.
  def self.title(work) = work&.title.presence || "a book"

  def self.edition_label(edition)
    [ edition.publisher.presence || "edition", edition.publish_date.to_s[0, 4].presence ].compact.join(" ")
  end
end

class Reading < ApplicationRecord
  # Full history: dates, ratings and status are entered in opsimath now,
  # not synced from Goodreads (docs/CATALOG.md, "Architecture review").
  has_paper_trail

  enum :status, { reading: "reading", completed: "completed", dnf: "dnf", paused: "paused" }
  enum :source, { owned_copy: "owned_copy", library: "library", borrowed: "borrowed", other: "other" }

  belongs_to :work
  belongs_to :edition
  belongs_to :copy, optional: true

  has_many :reviews, dependent: :nullify

  validates :status, presence: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
  validate :finished_after_started

  scope :unfinished, -> { where(status: %w[reading paused]) }

  def open? = reading? || paused?

  private

  def finished_after_started
    return unless date_started && date_finished && date_finished < date_started

    errors.add(:date_finished, "is before the start date")
  end
end

class Copy < ApplicationRecord
  has_paper_trail

  # `replaced` — swapped out for a better copy (of the same edition, or a
  # different edition of the same work). Distinct from sold/given_away in
  # recording *why* it left; set by Goodreads::EditionReconciliationResolver's
  # change_edition path. See docs/DATA_MODEL.md.
  enum :disposition, { owned: "owned", sold: "sold", given_away: "given_away", lost: "lost", replaced: "replaced" }

  # Short lozenge labels for the shared edition card (web + pocket).
  DISPOSITION_LABELS = {
    "owned" => "Owned", "sold" => "Sold", "given_away" => "Given away",
    "lost" => "Lost", "replaced" => "Replaced"
  }.freeze

  belongs_to :edition
  belongs_to :storage_location, optional: true

  has_many :readings, dependent: :restrict_with_error
end

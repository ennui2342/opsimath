class Copy < ApplicationRecord
  has_paper_trail

  # `replaced` — swapped out for a better copy (of the same edition, or a
  # different edition of the same work). Distinct from sold/given_away in
  # recording *why* it left; set by Goodreads::EditionReconciliationResolver's
  # change_edition path. See docs/DATA_MODEL.md.
  enum :disposition, { owned: "owned", sold: "sold", given_away: "given_away", lost: "lost", replaced: "replaced" }

  belongs_to :edition
  belongs_to :storage_location, optional: true

  has_many :readings, dependent: :restrict_with_error
end

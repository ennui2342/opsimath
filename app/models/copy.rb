class Copy < ApplicationRecord
  has_paper_trail

  enum :disposition, { owned: "owned", sold: "sold", given_away: "given_away", lost: "lost" }

  belongs_to :edition
  belongs_to :storage_location, optional: true

  has_many :readings, dependent: :restrict_with_error
end

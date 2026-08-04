class EditionContributor < ApplicationRecord
  belongs_to :edition
  belongs_to :contributor

  validates :role, presence: true
  validates :contributor_id, uniqueness: { scope: %i[edition_id role] }
end

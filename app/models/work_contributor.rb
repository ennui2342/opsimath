class WorkContributor < ApplicationRecord
  belongs_to :work
  belongs_to :contributor

  validates :role, presence: true
  validates :contributor_id, uniqueness: { scope: %i[work_id role] }
end

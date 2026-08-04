class Contributor < ApplicationRecord
  has_paper_trail

  has_many :work_contributors, dependent: :destroy
  has_many :edition_contributors, dependent: :destroy
  has_many :works, through: :work_contributors
  has_many :editions, through: :edition_contributors
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :name, presence: true
end

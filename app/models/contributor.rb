class Contributor < ApplicationRecord
  has_paper_trail

  has_many :work_contributors, dependent: :destroy
  has_many :edition_contributors, dependent: :destroy
  has_many :works, through: :work_contributors
  has_many :editions, through: :edition_contributors
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :name, presence: true

  # :living / :dead from the ISFDB author record (ContributorLifeRefresh),
  # :unknown when it couldn't be identified — CollectingProfile's buy-new
  # rule treats unknown as living. died_date is EDTF.
  def life_status
    return :dead if died_date.present?

    external_ids["isfdb"].present? ? :living : :unknown
  end
end

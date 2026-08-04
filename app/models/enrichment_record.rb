class EnrichmentRecord < ApplicationRecord
  belongs_to :entity, polymorphic: true

  validates :provider, presence: true
  validates :external_id, presence: true
  validates :fetched_at, presence: true
end

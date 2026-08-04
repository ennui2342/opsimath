class Series < ApplicationRecord
  has_paper_trail

  enum :status, { ongoing: "ongoing", complete: "complete" }

  has_many :series_arcs, dependent: :destroy
  has_many :work_series, dependent: :destroy
  has_many :works, through: :work_series
  has_many :wishlist_items, dependent: :nullify
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :name, presence: true
end

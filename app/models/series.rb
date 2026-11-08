class Series < ApplicationRecord
  has_paper_trail

  enum :status, { ongoing: "ongoing", complete: "complete" }

  has_many :series_arcs, dependent: :destroy
  has_many :work_series, dependent: :destroy
  has_many :works, through: :work_series
  has_many :enrichment_records, as: :entity, dependent: :destroy
  has_one :series_want, dependent: :destroy

  validates :name, presence: true
end

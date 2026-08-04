class SeriesArc < ApplicationRecord
  belongs_to :series

  has_many :work_series, foreign_key: :arc_id, inverse_of: :series_arc, dependent: :nullify
end

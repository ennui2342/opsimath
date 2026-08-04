class WorkSeries < ApplicationRecord
  belongs_to :work
  belongs_to :series
  belongs_to :series_arc, class_name: "SeriesArc", foreign_key: :arc_id, optional: true, inverse_of: :work_series
end

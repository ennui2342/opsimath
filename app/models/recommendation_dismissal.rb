# A recommendation Mark put off ("Not now": until a date) or ruled out
# ("Not for me": until nil).
class RecommendationDismissal < ApplicationRecord
  belongs_to :work

  scope :active, -> { where("until IS NULL OR until > ?", Time.current) }
end

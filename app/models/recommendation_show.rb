# A recommendation shown on a day, with its reason — the evidence for
# tuning the recommender later (did he start it?).
class RecommendationShow < ApplicationRecord
  belongs_to :work
end

# How many books Mark means to finish in a year (the home page's goal).
class ReadingGoal < ApplicationRecord
  validates :year, presence: true, uniqueness: true
  validates :target, numericality: { only_integer: true, greater_than: 0 }
end

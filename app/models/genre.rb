class Genre < ApplicationRecord
  has_many :work_genres, dependent: :destroy
  has_many :works, through: :work_genres

  validates :name, presence: true, uniqueness: true
end

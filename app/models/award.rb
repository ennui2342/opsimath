class Award < ApplicationRecord
  has_many :work_awards, dependent: :destroy
  has_many :works, through: :work_awards

  validates :name, presence: true
end

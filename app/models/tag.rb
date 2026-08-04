class Tag < ApplicationRecord
  has_many :work_tags, dependent: :destroy
  has_many :works, through: :work_tags

  validates :name, presence: true, uniqueness: true
end

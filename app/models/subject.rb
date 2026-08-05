class Subject < ApplicationRecord
  has_many :work_subjects, dependent: :destroy
  has_many :works, through: :work_subjects

  validates :name, presence: true, uniqueness: true
end

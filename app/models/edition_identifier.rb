class EditionIdentifier < ApplicationRecord
  belongs_to :edition

  validates :id_type, presence: true
  validates :value, presence: true
end

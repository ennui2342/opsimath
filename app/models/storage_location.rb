class StorageLocation < ApplicationRecord
  belongs_to :parent_location, class_name: "StorageLocation", optional: true
  has_many :child_locations, class_name: "StorageLocation", foreign_key: :parent_location_id, dependent: :nullify
  has_many :copies, dependent: :restrict_with_error

  validates :name, presence: true
end

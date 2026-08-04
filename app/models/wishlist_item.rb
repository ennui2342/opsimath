class WishlistItem < ApplicationRecord
  belongs_to :work, optional: true
  belongs_to :series, optional: true

  validates :title, presence: true
end

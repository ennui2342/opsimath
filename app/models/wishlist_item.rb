class WishlistItem < ApplicationRecord
  # cover_url stays the source-of-record link; cover_image is the stored
  # copy the shop-lookup PWA needs a :thumb from (docs/MOBILE.md).
  include HasCoverThumbnail

  belongs_to :work, optional: true
  belongs_to :series, optional: true

  validates :title, presence: true
end

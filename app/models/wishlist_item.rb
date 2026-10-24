class WishlistItem < ApplicationRecord
  # cover_url stays the source-of-record link; cover_image is the stored
  # copy the shop-lookup PWA needs a :thumb from (docs/MOBILE.md).
  include HasCoverThumbnail

  belongs_to :work, optional: true
  belongs_to :series, optional: true
  has_many :wishlist_printings, dependent: :destroy

  validates :title, presence: true

  # The ISBNs this item was wishlisted under, ISBN-13 first — the key into
  # ISFDB for its other printings (Isfdb::WishlistPrintingRefresh).
  def source_isbns
    external_ids.values_at("isbn13", "isbn10").compact_blank.uniq
  end

  # :living / :dead from the author's ISFDB record, :unknown when it
  # couldn't be identified (Isfdb::WishlistAuthorRefresh).
  def author_status
    return :dead if author_died_date.present?

    author_isfdb_id ? :living : :unknown
  end
end

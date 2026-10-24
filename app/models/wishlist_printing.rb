# One ISFDB printing of a wishlist book — the catalogue of what could turn
# up on eBay, cached per wishlist item by Isfdb::WishlistPrintingRefresh.
# Physical bindings only (ebook/audio rows are dropped at refresh time).
# Whether a printing is *wanted* isn't stored here: it's decided on read
# by CollectingProfile, so changing the profile or an item's override
# takes effect immediately. See docs/BARGAIN_HUNTING.md.
class WishlistPrinting < ApplicationRecord
  # ISFDB publisher names for book club editions — never wanted
  # (docs/BARGAIN_HUNTING.md, "What counts as wanted").
  BOOK_CLUB = /book club|\bsfbc\b|\bbca\b|\bbce\b|readers union|guild america|nelson doubleday/i
  A_FORMAT = "pb".freeze # ISFDB: mass-market paperback, <= 7.25" tall
  B_FORMAT = "tp".freeze # ISFDB: trade paperback — B-format, but also the larger C-format

  belongs_to :wishlist_item

  def year = publish_date.to_s[/\A\d{4}/]&.to_i

  def book_club? = publisher.to_s.match?(BOOK_CLUB)

  def a_format? = binding == A_FORMAT

  def b_format? = binding == B_FORMAT

  # Credited cover artists — ISFDB's list, joined ", " as Edition.cover_artist is.
  def artists = cover_artist.to_s.split(", ")
end

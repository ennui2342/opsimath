# One edition of a Work as a metadata provider knows it (docs/CATALOG.md,
# "Architecture review"): the candidates, as opposed to `editions`, which
# are the editions actually recorded in the catalogue. Serves the shop
# app's "you own a different edition" scan matching, the edition picker,
# and — once the wishlist joins the catalogue — bargain hunting. Refreshed
# per provider (KnownEditionsRefresh); pure derived data.
class ProviderEdition < ApplicationRecord
  belongs_to :work

  # ISFDB publisher names for book club editions — never wanted
  # (docs/BARGAIN_HUNTING.md, "What counts as wanted").
  BOOK_CLUB = /book club|\bsfbc\b|\bbca\b|\bbce\b|readers union|guild america|nelson doubleday/i
  # Bindings that aren't a physical book: ISFDB's ebook, "audio CD",
  # "digital audio download", …; Open Library's "Electronic resource", "MP3 CD", ….
  NON_PHYSICAL = /\Aebook\z|audio|electronic|mp3/i
  A_FORMAT = "pb".freeze # ISFDB: mass-market paperback, <= 7.25" tall
  B_FORMAT = "tp".freeze # ISFDB: trade paperback — B-format, but also the larger C-format

  def isbn = isbn13.presence || (isbn10.presence && Isbn.to_13(isbn10))

  def book_club? = publisher.to_s.match?(BOOK_CLUB)

  def physical? = binding.present? && !binding.match?(NON_PHYSICAL)

  def a_format? = binding == A_FORMAT

  def b_format? = binding == B_FORMAT

  # Credited cover artists, joined ", " as Edition.cover_artist is.
  def artists = cover_artist.to_s.split(", ")

  # The ISFDB pub id — the key bargain hunting's printing choices and eBay
  # identifications use (Want#printing_override_ids, EbayListing#matched_pub_ids).
  def isfdb_pub_id = provider == "isfdb" ? provider_id.to_i : nil

  # A printing bargain hunting reasons about: ISFDB's, physical. (Open
  # Library's editions lack reliable formats; they join when the edition
  # picker groups providers by cover.)
  def hunted_printing? = provider == "isfdb" && physical?

  def year = publish_date.to_s[/\A\d{4}/]&.to_i

  # {work_id => [ISBN-13, ...]} across every provider, for the works given.
  def self.isbns_by_work(work_ids)
    where(work_id: work_ids).order(:id).pluck(:work_id, :isbn13, :isbn10)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(work_id, i13, i10), out|
        isbn = i13.presence || (i10.presence && Isbn.to_13(i10))
        out[work_id] << isbn if isbn && !out[work_id].include?(isbn)
      end
  end
end

# One edition of a Work as a metadata provider knows it (docs/CATALOG.md,
# "Architecture review"): the candidates, as opposed to `editions`, which
# are the editions actually recorded in the catalogue. Serves the shop
# app's "you own a different edition" scan matching, the edition picker,
# and — once the wishlist joins the catalogue — bargain hunting. Refreshed
# per provider (KnownEditionsRefresh); pure derived data.
class ProviderEdition < ApplicationRecord
  belongs_to :work

  def isbn = isbn13.presence || (isbn10.presence && Isbn.to_13(isbn10))

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

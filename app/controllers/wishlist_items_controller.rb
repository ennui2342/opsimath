# The wishlist and, per book, the cover picker (docs/BARGAIN_HUNTING.md,
# "Front end"). Phone-first: reached mostly from Discord links. The book
# page's job is choosing which covers to hunt and at what price, with the
# current eBay listings alongside to decide against.
class WishlistItemsController < ApplicationController
  def index
    profile = CollectingProfile.current
    wants = Want.includes(work: [ :provider_editions, :ebay_listings, { work_contributors: :contributor } ])
    @views = wants.map { |want| WishlistItemView.new(want, profile:) }
  end

  def show
    @view = WishlistItemView.new(find_want)
  end

  def update
    want = find_want
    view = WishlistItemView.new(want)
    chosen = Array(params[:covers]).map(&:to_i)
    want.update!(
      printing_override_ids: view.covers.any? ? WishlistItemView.override_for(view, chosen) : want.printing_override_ids,
      target_price: pence(params[:target_price]),
      buy_new_override: { "hunt" => false, "buy_new" => true }[params[:buy_new]]
    )
    redirect_to wishlist_item_path(want), notice: "Saved."
  end

  private

  # The wishlist's ids are Want ids (the URL stays /wishlist).
  def find_want = Want.includes(work: [ :provider_editions, :ebay_listings, { work_contributors: :contributor } ]).find(params[:id])

  # "£4.50" / "4.5" / "" -> 450 / 450 / nil
  def pence(value)
    amount = value.to_s.delete("£, ").presence
    amount && (BigDecimal(amount) * 100).round
  rescue ArgumentError
    nil
  end
end

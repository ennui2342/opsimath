# The wishlist and, per book, the cover picker (docs/BARGAIN_HUNTING.md,
# "Front end"). Phone-first: reached mostly from Discord links. The book
# page's job is choosing which covers to hunt and at what price, with the
# current eBay listings alongside to decide against.
class WishlistItemsController < ApplicationController
  def index
    profile = CollectingProfile.current
    items = WishlistItem.includes(:wishlist_printings, :ebay_listings).order(:title)
    @views = items.map { |item| WishlistItemView.new(item, profile:) }
  end

  def show
    @view = WishlistItemView.new(find_item)
  end

  def update
    item = find_item
    view = WishlistItemView.new(item)
    chosen = Array(params[:covers]).map(&:to_i)
    item.update!(
      printing_override_ids: view.covers.any? ? WishlistItemView.override_for(view, chosen) : item.printing_override_ids,
      target_price: pence(params[:target_price]),
      buy_new_override: { "hunt" => false, "buy_new" => true }[params[:buy_new]]
    )
    redirect_to wishlist_item_path(item), notice: "Saved."
  end

  private

  def find_item = WishlistItem.includes(:wishlist_printings, :ebay_listings).find(params[:id])

  # "£4.50" / "4.5" / "" -> 450 / 450 / nil
  def pence(value)
    amount = value.to_s.delete("£, ").presence
    amount && (BigDecimal(amount) * 100).round
  rescue ArgumentError
    nil
  end
end

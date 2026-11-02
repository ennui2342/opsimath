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

  # "Not this cover", from a find card: the cover leaves the book's
  # chosen covers — the same as unticking it on the book's page — and
  # every find on it goes; the clicked card becomes a one-line undo.
  def drop_cover
    want = find_want
    view = WishlistItemView.new(want)
    cover_id = params[:cover_id].to_i
    choose(want, view, view.covers.select(&:chosen).map(&:id) - [ cover_id ])
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(params[:card].to_s[/\Aebay_listing_\d+\z/] || "none", partial: "wishlist_items/cover_dropped",
                                                                  locals: { want:, cover: view.covers.find { |c| c.id == cover_id } }),
          turbo_stream.remove_all(".#{helpers.find_cover_class(want, cover_id)}")
        ]
      end
      format.html { redirect_to finds_path, notice: "No longer wanting that cover of “#{want.title}”." }
    end
  end

  def restore_cover
    want = find_want
    view = WishlistItemView.new(want)
    choose(want, view, view.covers.select(&:chosen).map(&:id) | [ params[:cover_id].to_i ])
    redirect_to finds_path, notice: "Wanting that cover of “#{want.title}” again."
  end

  private

  def choose(want, view, cover_ids)
    want.update!(printing_override_ids: WishlistItemView.override_for(view, cover_ids)) if view.covers.any?
  end

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

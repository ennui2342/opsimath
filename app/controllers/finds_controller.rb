# The Finds queue (docs/BARGAIN_HUNTING.md): eBay listings on covers Mark
# wants that are under his target price or well below their cover's
# usual price. Phone-first — Discord notifications will link here.
class FindsController < ApplicationController
  # `by=seller`: grouped by seller, those with several finds first — to buy
  # together and save postage.
  def index
    @finds = Finds.all
    @by_seller = params[:by] == "seller"
    @seller_counts = @finds.filter_map { |f| f.listing.seller }.tally
    return unless @by_seller

    @groups = @finds.group_by { |f| f.listing.seller }.sort_by { |seller, finds| [ seller ? 0 : 1, -finds.size, seller.to_s.downcase ] }
  end
end

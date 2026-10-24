# Mark's corrections to an eBay listing (docs/BARGAIN_HUNTING.md, "/finds"):
# dismiss it, or say which printing it really is. A correction is
# identified_by "manual", which Ebay::PrintingIdentifier never revisits;
# the cover scores stay on the row, so corrections show how well the
# automatic identification is doing.
class EbayListingsController < ApplicationController
  before_action :set_listing

  def dismiss
    @listing.update!(status: "dismissed")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(helpers.dom_id(@listing)) }
      format.html { redirect_to finds_path, notice: "Dismissed." }
    end
  end

  def edit
    @covers = @listing.wishlist_item.wishlist_printings
                      .group_by { |p| [ p.binding, p.cover_group || p.isfdb_pub_id ] }
                      .sort_by { |(format_code, _), ps| [ format_code, ps.filter_map(&:year).min || 9999 ] }
  end

  def update
    case params[:printing]
    when "not_this_book"
      @listing.update!(matched_pub_ids: [], identified_by: "manual", status: "wrong_book")
    when "unknown"
      @listing.update!(matched_pub_ids: [], identified_by: "manual")
    else
      ids = params[:printing].to_s.split(",").map(&:to_i)
      known = @listing.wishlist_item.wishlist_printings.map(&:isfdb_pub_id)
      @listing.update!(matched_pub_ids: ids & known, identified_by: "manual")
    end
    redirect_to finds_path, notice: "Updated “#{@listing.title.truncate(40)}”."
  end

  private

  def set_listing
    @listing = EbayListing.includes(wishlist_item: :wishlist_printings).find(params[:id])
  end
end

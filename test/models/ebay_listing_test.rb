require "test_helper"

class EbayListingTest < ActiveSupport::TestCase
  test "link is the URL only for an https eBay link — it comes from eBay's API and goes into hrefs" do
    assert_equal "https://www.ebay.co.uk/itm/1", EbayListing.new(url: "https://www.ebay.co.uk/itm/1").link
    assert_equal "https://ebay.com/itm/1", EbayListing.new(url: "https://ebay.com/itm/1").link
    assert_nil EbayListing.new(url: "javascript:alert(1)").link
    assert_nil EbayListing.new(url: "http://www.ebay.co.uk/itm/1").link
    assert_nil EbayListing.new(url: "https://www.ebay.co.uk.evil.test/itm/1").link
    assert_nil EbayListing.new(url: "https://not a url").link
    assert_nil EbayListing.new(url: nil).link
  end

  test "total is the current bid for an auction, else the price, plus postage" do
    assert_equal 720, EbayListing.new(price: 450, shipping: 270).total
    assert_equal 1204, EbayListing.new(price: 1294, current_bid: 866, shipping: 338, buying_options: %w[FIXED_PRICE AUCTION]).total
    assert_nil EbayListing.new(price: nil).total
  end
end

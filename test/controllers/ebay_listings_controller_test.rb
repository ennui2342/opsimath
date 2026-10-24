require "test_helper"

class EbayListingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", author_isfdb_id: 105, author_died_date: "2015")
    @item.wishlist_printings.create!(isfdb_pub_id: 1, binding: "pb", publish_date: "1977", publisher: "Orbit", cover_group: 1)
    @item.wishlist_printings.create!(isfdb_pub_id: 2, binding: "pb", publish_date: "1979", publisher: "Orbit", cover_group: 2)
    @item.wishlist_printings.create!(isfdb_pub_id: 3, binding: "pb", publish_date: "1985", publisher: "Orbit", cover_group: 2)
    now = Time.current
    @listing = @item.ebay_listings.create!(ebay_item_id: "x", title: "The Birthgrave Orbit", url: "https://ebay.test/x", price: 500,
                                           found_by: "keyword", matched_pub_ids: [ 1 ], identified_by: "cover",
                                           cover_scores: { "1" => { "ratio" => 0.1, "inliers" => 40 } }, first_seen_at: now, last_seen_at: now)
    sign_in_as users(:one)
  end

  test "dismiss removes the card in place" do
    post dismiss_ebay_listing_url(@listing), as: :turbo_stream

    assert_equal "dismissed", @listing.reload.status
    assert_match %(<turbo-stream action="remove" target="ebay_listing_#{@listing.id}">), response.body
  end

  test "edit offers each cover once, the current match selected" do
    get edit_ebay_listing_url(@listing)

    assert_response :success
    assert_select "input[type=radio][name=printing]", count: 4 # two covers + can't tell + not this book
    assert_select "input[type=radio][value='1'][checked]"
    assert_select "input[type=radio][value='2,3']"
  end

  test "re-assigning to another cover records a manual identification, keeping the scores" do
    patch ebay_listing_url(@listing), params: { printing: "2,3" }

    assert_redirected_to finds_path
    @listing.reload
    assert_equal [ 2, 3 ], @listing.matched_pub_ids.sort
    assert_equal "manual", @listing.identified_by
    assert_equal 0.1, @listing.cover_scores["1"]["ratio"]
  end

  test "not this book takes it out of the hunt" do
    patch ebay_listing_url(@listing), params: { printing: "not_this_book" }

    @listing.reload
    assert_equal [ "wrong_book", [], "manual" ], [ @listing.status, @listing.matched_pub_ids, @listing.identified_by ]
  end

  test "printing ids from another book are ignored" do
    patch ebay_listing_url(@listing), params: { printing: "2,999" }

    assert_equal [ 2 ], @listing.reload.matched_pub_ids
  end
end

require "test_helper"

class EbayListingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = create_want
    author_dead!(@item, "2015")
    add_printing(@item, 1, binding: "pb", publish_date: "1977", publisher: "Orbit", cover_group: "1")
    add_printing(@item, 2, binding: "pb", publish_date: "1979", publisher: "Orbit", cover_group: "2")
    add_printing(@item, 3, binding: "pb", publish_date: "1985", publisher: "Orbit", cover_group: "2")
    now = Time.current
    @listing = @item.work.ebay_listings.create!(ebay_item_id: "x", title: "The Birthgrave Orbit", url: "https://www.ebay.co.uk/itm/x", price: 500,
                                           found_by: "keyword", matched_pub_ids: [ 1 ], identified_by: "cover",
                                           cover_scores: { "1" => { "ratio" => 0.1, "inliers" => 40 } }, first_seen_at: now, last_seen_at: now)
    sign_in_as users(:one)
  end

  test "dismiss swaps the card for an undo, and undo restores it" do
    post dismiss_ebay_listing_url(@listing), as: :turbo_stream

    assert_equal "dismissed", @listing.reload.status
    assert_match %(<turbo-stream action="replace" target="ebay_listing_#{@listing.id}">), response.body
    assert_match restore_ebay_listing_path(@listing), response.body

    post restore_ebay_listing_url(@listing)

    assert_redirected_to finds_path
    assert_equal "new", @listing.reload.status
  end

  test "undo only brings back a dismissed listing" do
    @listing.update!(status: "wrong_book")

    post restore_ebay_listing_url(@listing)

    assert_equal "wrong_book", @listing.reload.status
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

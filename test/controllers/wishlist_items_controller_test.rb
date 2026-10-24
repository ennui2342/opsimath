require "test_helper"

class WishlistItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", author_isfdb_id: 105, author_died_date: "2015-05-24")
    @item.wishlist_printings.create!(isfdb_pub_id: 1, binding: "pb", publish_date: "1977-09", publisher: "Orbit",
                                     cover_artist: "Gino D'Achille", cover_url: "https://covers.test/77.jpg", cover_group: 1)
    @item.wishlist_printings.create!(isfdb_pub_id: 2, binding: "pb", publish_date: "1979", publisher: "Orbit",
                                     cover_artist: "Peter Jones", cover_url: "https://covers.test/79.jpg", cover_group: 2)
    @item.wishlist_printings.create!(isfdb_pub_id: 3, binding: "pb", publish_date: "1985", publisher: "Orbit",
                                     cover_artist: "Peter Jones", cover_url: "https://covers.test/79.jpg", cover_group: 2)
    @item.wishlist_printings.create!(isfdb_pub_id: 4, binding: "tp", publish_date: "2010", publisher: "TaLeKa", cover_group: 4)
    now = Time.current
    @item.ebay_listings.create!(ebay_item_id: "a", title: "The Birthgrave Orbit 1979", url: "https://www.ebay.co.uk/itm/a", price: 450, shipping: 270,
                                found_by: "keyword", matched_pub_ids: [ 2, 3 ], identified_by: "cover", first_seen_at: now, last_seen_at: now)
    @item.ebay_listings.create!(ebay_item_id: "b", title: "Birthgrave TaLeKa trade paperback", url: "https://www.ebay.co.uk/itm/b", price: 900,
                                found_by: "keyword", matched_pub_ids: [ 4 ], identified_by: "text", first_seen_at: now, last_seen_at: now)
    @item.ebay_listings.create!(ebay_item_id: "c", title: "Birthgrave tanith lee pb", url: "https://www.ebay.co.uk/itm/c", price: 300,
                                found_by: "keyword", identified_by: "unknown", first_seen_at: now, last_seen_at: now)
    sign_in_as users(:one)
  end

  test "index lists the wishlist with each hunted book's chosen covers" do
    get wishlist_items_url

    assert_response :success
    assert_select "a[href=?]", wishlist_item_path(@item), text: /The Birthgrave/
    assert_select "span", text: "2/2 covers"
  end

  test "show offers one card per A-format cover, listings on their cover, the rest set apart" do
    get wishlist_item_url(@item)

    assert_response :success
    assert_select "input[type=checkbox][name='covers[]']", count: 2 # the 1979/1985 Orbits share a cover; the tp isn't offered
    assert_select "input[type=checkbox][value='2'][checked]"
    assert_select "a[href='https://www.ebay.co.uk/itm/a']", text: /£4.50 \+ £2.70/
    assert_select "h2", text: /Other printings and formats \(1\)/
    assert_select "h2", text: /Printing unknown \(1\)/
  end

  test "saving a subset of covers stores those printings; target price in pence; buy-new choice" do
    patch wishlist_item_url(@item), params: { covers: [ "2" ], target_price: "£6.50", buy_new: "hunt" }

    assert_redirected_to wishlist_item_path(@item)
    @item.reload
    assert_equal [ 2, 3 ], @item.printing_override_ids.sort
    assert_equal 650, @item.target_price
    assert_equal false, @item.buy_new_override
  end

  test "choosing every cover clears the override, so the rule stays in charge" do
    @item.update!(printing_override_ids: [ 2, 3 ])

    patch wishlist_item_url(@item), params: { covers: [ "1", "2" ], target_price: "", buy_new: "rule" }

    @item.reload
    assert_nil @item.printing_override_ids
    assert_nil @item.target_price
    assert_nil @item.buy_new_override
  end

  test "requires login" do
    sign_out
    get wishlist_items_url
    assert_redirected_to new_session_path
  end
end

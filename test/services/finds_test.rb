require "test_helper"

class FindsTest < ActiveSupport::TestCase
  setup do
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", author_isfdb_id: 105, author_died_date: "2015")
    @item.wishlist_printings.create!(isfdb_pub_id: 2, binding: "pb", publish_date: "1979", publisher: "Orbit", cover_group: 2)
    @item.wishlist_printings.create!(isfdb_pub_id: 4, binding: "pb", publish_date: "1981", publisher: "DAW Books", cover_group: 4)
  end

  def listing(total, pubs = [ 2 ], **attrs)
    now = Time.current
    @item.ebay_listings.create!({ ebay_item_id: SecureRandom.hex(4), title: "The Birthgrave", price: total, shipping: 0,
                                  found_by: "keyword", matched_pub_ids: pubs, identified_by: "cover",
                                  first_seen_at: now, last_seen_at: now }.merge(attrs))
  end

  test "a listing well below the median of its own cover's listings is a find" do
    cheap = listing(500)
    [ 1200, 1400, 1500 ].each { |p| listing(p) }
    listing(100, [ 4 ]) # another cover — doesn't count towards cover 2's median, and is alone on its own

    finds = Finds.all

    assert_equal [ cheap ], finds.map(&:listing)
    assert_equal :spread, finds.first.reason
    assert_equal 1300, finds.first.median
    assert_equal 4, finds.first.count
  end

  test "only a cover's cheapest listing is a spread find — the rest are its going rate" do
    cheapest = listing(350)
    listing(360)
    [ 1200, 1400, 1500 ].each { |p| listing(p) }

    assert_equal [ cheapest ], Finds.all.map(&:listing)
  end

  test "too few listings of a cover to judge: no spread find" do
    listing(100)
    listing(1500)

    assert_empty Finds.all
  end

  test "at or under the target price is a find whatever the spread, and sorts first" do
    @item.update!(target_price: 450)
    under = listing(400, [ 4 ])
    cheap = listing(500)
    [ 1200, 1400, 1500 ].each { |p| listing(p) }

    assert_equal [ under, cheap ], Finds.all.map(&:listing)
    assert_equal :target, Finds.all.first.reason
  end

  test "dismissed, ended, and unwanted-cover listings are never finds" do
    @item.update!(target_price: 2000, printing_override_ids: [ 2 ]) # cover 4 not wanted
    listing(500, [ 4 ])
    listing(500, status: "dismissed")
    listing(500, ended_at: 1.hour.ago)
    kept = listing(600)

    assert_equal [ kept ], Finds.all.map(&:listing)
  end
end

require "test_helper"

class WishlistCoverGroupingTest < ActiveSupport::TestCase
  # "Same cover" when both images' bytes (the stubbed download is the
  # URL's last path segment) start with the same letter.
  class FakeCompare
    attr_reader :calls

    def initialize = @calls = 0

    def compare(a, b)
      @calls += 1
      same = a[0] == b[0]
      Enrichment::CoverCompareClient::Result.new(ratio: same ? 0.3 : 0.0, inliers: same ? 600 : 0)
    end
  end

  setup do
    stub_request(:get, %r{https://covers\.test/.*}).to_return { |req| { status: 200, body: req.uri.path.split("/").last } }
    @profile = CollectingProfile.new(recent_years: 5, favourite_artist_min_owned: 5)
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", author_isfdb_id: 1, author_died_date: "2015")
  end

  def printing(pub_id, binding, year, cover)
    @item.wishlist_printings.create!(isfdb_pub_id: pub_id, binding:, publish_date: year,
                                     cover_url: cover && "https://covers.test/#{cover}")
  end

  def group(compare = FakeCompare.new) = WishlistCoverGrouping.new(compare:, profile: @profile).run

  test "printings with the same art share the earliest printing's group, within a binding" do
    printing(1, "pb", "1977", "skull-77")
    printing(2, "pb", "1979", "ophis-79")
    printing(3, "pb", "1985", "ophis-79")   # same URL
    printing(4, "pb", "1986", "skull-86")   # same art, different scan
    printing(5, "tp", "2010", "skull-tp")   # same art, other binding
    printing(6, "pb", "1990", nil)          # no cover

    group

    groups = @item.wishlist_printings.order(:isfdb_pub_id).pluck(:isfdb_pub_id, :cover_group).to_h
    assert_equal({ 1 => 1, 2 => 2, 3 => 2, 4 => 1, 5 => 5, 6 => 6 }, groups)
  end

  test "a book is regrouped only when its printings change" do
    printing(1, "pb", "1977", "skull-77")
    printing(2, "pb", "1979", "ophis-79")
    group

    compare = FakeCompare.new
    assert_equal 0, group(compare).grouped
    assert_equal 0, compare.calls

    printing(3, "pb", "1985", "web-85")
    assert_equal 1, group.grouped
    assert_equal 3, @item.wishlist_printings.find_by(isfdb_pub_id: 3).cover_group
  end

  test "books that aren't hunted are left alone" do
    @item.update!(author_died_date: nil) # living author, no A-format: buy new
    printing(1, "tp", "1977", "skull-77")

    assert_equal 0, group.hunted
    assert_nil @item.wishlist_printings.first.cover_group
  end
end

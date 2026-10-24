require "test_helper"

class FindsDigestTest < ActiveSupport::TestCase
  class Recorder
    attr_reader :events

    def initialize = @events = []
    def notify(event) = @events << event
  end

  setup do
    @recorder = Recorder.new
    Notifications.notifiers = [ @recorder ]
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee", author_isfdb_id: 105, author_died_date: "2015")
    @item.wishlist_printings.create!(isfdb_pub_id: 2, binding: "pb", publish_date: "1979", publisher: "Orbit",
                                     cover_artist: "Peter Jones", cover_group: 2)
    now = Time.current
    @cheap = listing(500, now)
    [ 1200, 1400, 1500 ].each { |p| listing(p, now) }
  end

  teardown { Notifications.notifiers = nil }

  def listing(total, now)
    @item.ebay_listings.create!(ebay_item_id: SecureRandom.hex(4), title: "The Birthgrave", url: "https://www.ebay.co.uk/itm/#{total}",
                                price: total, shipping: 0, found_by: "keyword", matched_pub_ids: [ 2 ], identified_by: "cover",
                                first_seen_at: now, last_seen_at: now)
  end

  test "announces new finds once, linking to the finds page" do
    assert_equal 1, FindsDigest.run

    event = @recorder.events.sole
    assert_equal "eBay: 1 new find", event.title
    assert_equal "http://www.example.com/finds", event.url
    assert_includes event.description, "**The Birthgrave** — Peter Jones · £5.00 (38% of usual £13.00) · [eBay](https://www.ebay.co.uk/itm/500)"
    assert_not_nil @cheap.reload.notified_at

    assert_equal 0, FindsDigest.run
    assert_equal 1, @recorder.events.size
  end

  test "nothing to announce sends nothing" do
    @cheap.update!(notified_at: 1.day.ago)

    assert_equal 0, FindsDigest.run
    assert_empty @recorder.events
  end
end

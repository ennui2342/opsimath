require "test_helper"

module Mobile
  class WishlistCoverBackfillTest < ActiveSupport::TestCase
    FEED_ITEM = Goodreads::RssClient::FeedItem.new(
      goodreads_book_id: "111", title: "In The Feed", author_name: "A",
      book_image_url: "https://i.gr-assets.com/feed-cover.jpg"
    )

    setup do
      @in_feed = WishlistItem.create!(title: "In The Feed", external_ids: { "goodreads" => "111" })
      @scraped = WishlistItem.create!(title: "Off The Feed", external_ids: { "goodreads" => "222" })
      @no_goodreads = WishlistItem.create!(title: "Manual Add")
      stub_request(:get, "https://i.gr-assets.com/feed-cover.jpg").to_return(status: 200, body: "feed-bytes", headers: { "Content-Type" => "image/jpeg" })
    end

    test "uses the RSS feed image when the item is in it, and the Goodreads page og:image otherwise" do
      stub_request(:get, "https://www.goodreads.com/book/show/222")
        .to_return(status: 200, body: %(<meta property="og:image" content="https://images.example/og.jpg">))
      stub_request(:get, "https://images.example/og.jpg").to_return(status: 200, body: "og-bytes", headers: { "Content-Type" => "image/jpeg" })

      result = WishlistCoverBackfill.run(feed: [ FEED_ITEM ], throttle: 0)

      assert_equal "feed-bytes", @in_feed.reload.cover_image.download
      assert_equal "og-bytes", @scraped.reload.cover_image.download
      assert_equal "https://i.gr-assets.com/feed-cover.jpg", @in_feed.cover_url
      assert_equal 2, result.attached
    end

    test "skips items that already have a cover — safe to re-run" do
      @in_feed.cover_image.attach(io: StringIO.new("existing"), filename: "e.jpg", content_type: "image/jpeg")
      stub_request(:get, "https://www.goodreads.com/book/show/222").to_return(status: 404)

      result = WishlistCoverBackfill.run(feed: [ FEED_ITEM ], throttle: 0)

      assert_equal "existing", @in_feed.reload.cover_image.download # untouched
      assert_equal 1, result.failed # @scraped: 404
    end

    test "a 'no cover' Goodreads placeholder is not attached" do
      stub_request(:get, "https://www.goodreads.com/book/show/222")
        .to_return(status: 200, body: %(<meta property="og:image" content="https://www.goodreads.com/assets/nophoto/book/111.png">))

      result = WishlistCoverBackfill.run(feed: [ FEED_ITEM ], throttle: 0)

      assert_not @scraped.reload.cover_image.attached?
      assert_equal 1, result.attached # only @in_feed
    end

    test "items with no goodreads id are left alone" do
      stub_request(:get, %r{goodreads\.com/book/show}).to_return(status: 404)
      WishlistCoverBackfill.run(feed: [], throttle: 0)
      assert_not @no_goodreads.reload.cover_image.attached?
    end
  end
end

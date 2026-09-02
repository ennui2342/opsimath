require "test_helper"

module Mobile
  class WishlistCoverBackfillTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    FEED_ITEM = Goodreads::RssClient::FeedItem.new(
      goodreads_book_id: "111", title: "In The Feed", author_name: "A",
      book_image_url: "https://i.gr-assets.com/feed-cover.jpg"
    )

    setup do
      @client = Isfdb::Client.new(base_url: BASE_URL)
      @in_feed = WishlistItem.create!(title: "In The Feed", external_ids: { "goodreads" => "111" })
      @via_isfdb = WishlistItem.create!(title: "Off The Feed",
                                        external_ids: { "goodreads" => "222", "isbn13" => "9780765304674" })
      @no_lookup = WishlistItem.create!(title: "Manual Add") # no goodreads id, no isbn

      stub_request(:get, "https://i.gr-assets.com/feed-cover.jpg")
        .to_return(status: 200, body: "feed-bytes", headers: { "Content-Type" => "image/jpeg" })
    end

    def stub_isbn(isbn, cover_url:)
      stub_request(:get, "#{BASE_URL}/isbn/#{isbn}?all=true").to_return(
        status: 200,
        body: [ { title: "X", cover_url: cover_url } ].to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end

    test "RSS feed image first, then the ISFDB cover for the item's ISBN" do
      stub_isbn("9780765304674", cover_url: "https://www.isfdb.org/wiki/images/x/cover.jpg")
      stub_request(:get, "https://www.isfdb.org/wiki/images/x/cover.jpg")
        .to_return(status: 200, body: "isfdb-bytes", headers: { "Content-Type" => "image/jpeg" })

      result = WishlistCoverBackfill.run(feed: [ FEED_ITEM ], client: @client)

      assert_equal "feed-bytes", @in_feed.reload.cover_image.download
      assert_equal "isfdb-bytes", @via_isfdb.reload.cover_image.download
      assert_equal "https://i.gr-assets.com/feed-cover.jpg", @in_feed.cover_url
      assert_equal "https://www.isfdb.org/wiki/images/x/cover.jpg", @via_isfdb.cover_url
      assert_equal 2, result.attached
    end

    test "skips items that already have a cover — safe to re-run" do
      @in_feed.cover_image.attach(io: StringIO.new("existing"), filename: "e.jpg", content_type: "image/jpeg")
      stub_isbn("9780765304674", cover_url: "")

      result = WishlistCoverBackfill.run(feed: [ FEED_ITEM ], client: @client)

      assert_equal "existing", @in_feed.reload.cover_image.download # untouched
      assert_equal 1, result.failed # @via_isfdb: ISFDB has no cover_url
    end

    test "an ISBN the ISFDB mirror doesn't know is a clean failure, not an error" do
      stub_request(:get, "#{BASE_URL}/isbn/9780765304674?all=true").to_return(status: 404)

      result = WishlistCoverBackfill.run(feed: [], client: @client)

      assert_not @via_isfdb.reload.cover_image.attached?
      assert_equal 2, result.failed # @in_feed (no feed match, no isbn) and @via_isfdb (404) — both clean
    end

    test "items with nothing to look up are left alone" do
      stub_request(:get, "#{BASE_URL}/isbn/9780765304674?all=true").to_return(status: 404)

      result = WishlistCoverBackfill.run(feed: [], client: @client)

      assert_not @no_lookup.reload.cover_image.attached?
      assert_equal 1, result.skipped # @no_lookup never entered the pending scope
    end
  end
end

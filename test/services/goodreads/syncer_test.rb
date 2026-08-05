require "test_helper"

module Goodreads
  class SyncerTest < ActiveSupport::TestCase
    class FixtureRssClient
      FILE_NAMES = {
        "wishlist" => "wishlist", "to-read" => "to_read", "currently-reading" => "currently_reading",
        "read" => "read", "did-not-finish" => "did_not_finish"
      }.freeze

      def fetch(shelf)
        client = RssClient.allocate
        body = File.read(Rails.root.join("test/fixtures/files/goodreads_#{FILE_NAMES.fetch(shelf)}_sample.xml"))
        client.send(:parse, body)
      end
    end

    setup do
      Subject.create!(name: "Fiction", ddc_code: "800")
    end

    test "a full sync run creates a GoodreadsSyncState row per real feed item" do
      result = Syncer.sync(rss_client: FixtureRssClient.new)

      # 2+2+2+1+1 real items across the 5 fixture files
      assert_equal 8, result[:counts].synced
      assert_equal 0, result[:counts].unchanged
      assert_equal 8, GoodreadsSyncState.count
    end

    test "an immediate second run is a no-op — confirms the diff, not just that the first run did something" do
      Syncer.sync(rss_client: FixtureRssClient.new)
      result = Syncer.sync(rss_client: FixtureRssClient.new)

      assert_equal 0, result[:counts].synced
      assert_equal 8, result[:counts].unchanged
    end

    test "a reverted rating re-triggers a sync rather than looking already-handled" do
      Syncer.sync(rss_client: FixtureRssClient.new)
      state = GoodreadsSyncState.find_by!(goodreads_book_id: "953070", shelf: "read")
      # Simulate Goodreads reporting a different rating on the next poll
      state.update!(last_synced_payload: state.last_synced_payload.merge("user_rating" => 1.0))

      result = Syncer.sync(rss_client: FixtureRssClient.new)

      assert_equal 1, result[:counts].synced
      assert_equal 5.0, state.reload.last_synced_payload["user_rating"] # back to the feed's real value
    end
  end
end

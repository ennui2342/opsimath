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

    # Mark, 2026-08-08: "a cover image appearing in the rss feed where
    # there wasn't one before means an update to the enrichment record
    # which then triggers an attempted sync to the edition. Any update
    # to the enrichment should then flow into the standard match/conflict
    # workflow." Without book_image_url in relevant_fields, this item
    # would look "already handled" forever once its rating/review/dates
    # stop changing, and Goodreads::ShelfSync#record_goodreads_cover would
    # never get a chance to run again.
    test "a cover appearing where the feed previously had none re-triggers a sync and backfills it" do
      Syncer.sync(rss_client: FixtureRssClient.new)
      state = GoodreadsSyncState.find_by!(goodreads_book_id: "39666185", shelf: "to-read")
      edition = EditionIdentifier.find_by!(id_type: "goodreads", value: "39666185").edition
      assert edition.cover_image.attached? # the real fixture cover, already filled on the first sync
      # Simulate the feed having no cover the *first* time this was synced
      state.update!(last_synced_payload: state.last_synced_payload.merge("book_image_url" => nil))
      edition.cover_image.purge
      edition.update!(field_sources: edition.field_sources.except("cover_image"))

      result = Syncer.sync(rss_client: FixtureRssClient.new)

      assert_equal 1, result[:counts].synced
      assert edition.reload.cover_image.attached? # backfilled via the standard fill/conflict workflow
      assert_equal "goodreads", edition.field_sources["cover_image"]
    end
  end
end

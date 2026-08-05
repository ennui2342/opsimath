module Goodreads
  # Orchestrates one full Phase 2 sync run — see docs/INTEGRATIONS.md.
  # Fetches all 5 shelves, diffs each item against the last-synced
  # snapshot (never a permanent "seen" set — a reverted value must not
  # look "already handled"), and dispatches only genuinely new/changed
  # items to ShelfSync.
  class Syncer
    SHELVES = %w[wishlist to-read currently-reading read did-not-finish].freeze

    Touched = Struct.new(:shelf, :goodreads_book_id, :title, :entity, :edition, :created, keyword_init: true)
    Counts = Struct.new(:synced, :unchanged, keyword_init: true) do
      def to_s
        "synced=#{synced} unchanged=#{unchanged}"
      end
    end

    def self.sync(rss_client: RssClient.new)
      new(rss_client).sync
    end

    def initialize(rss_client)
      @rss_client = rss_client
    end

    def sync
      counts = Counts.new(synced: 0, unchanged: 0)
      touched = []

      SHELVES.each { |shelf| sync_shelf(shelf, counts, touched) }

      { counts: counts, touched: touched }
    end

    private

    # One batched GoodreadsSyncState lookup per shelf, not one per item —
    # per the doc's explicit efficiency requirement.
    def sync_shelf(shelf, counts, touched)
      items = @rss_client.fetch(shelf)
      states = GoodreadsSyncState.where(shelf: shelf, goodreads_book_id: items.map(&:goodreads_book_id))
                                 .index_by(&:goodreads_book_id)

      items.each do |item|
        state = states[item.goodreads_book_id]
        new_fields = relevant_fields(shelf, item)

        if state && state.last_synced_payload.slice(*new_fields.keys) == new_fields
          counts.unchanged += 1
          next
        end

        outcome = ShelfSync.sync(item, shelf, state&.last_synced_payload || {})
        upsert_state(shelf, item.goodreads_book_id, new_fields.merge(outcome.payload))
        counts.synced += 1
        touched << Touched.new(
          shelf: shelf, goodreads_book_id: item.goodreads_book_id, title: item.title,
          entity: outcome.entity, edition: outcome.edition, created: outcome.created
        )
      end
    end

    # Shape depends on shelf, per docs/INTEGRATIONS.md — only the fields
    # that actually signal a meaningful change for that shelf are tracked;
    # e.g. a read-shelf item's rating/review can be edited after the fact
    # (or reverted), which must re-trigger a sync, not look "already seen".
    def relevant_fields(shelf, item)
      case shelf
      when "wishlist", "to-read"
        {}
      when "currently-reading"
        { "user_date_added" => item.user_date_added&.iso8601 }
      when "read", "did-not-finish"
        { "user_rating" => item.user_rating, "user_read_at" => item.user_read_at&.iso8601, "user_review" => item.user_review }
      end
    end

    def upsert_state(shelf, goodreads_book_id, payload)
      state = GoodreadsSyncState.find_or_initialize_by(shelf: shelf, goodreads_book_id: goodreads_book_id)
      state.update!(last_synced_payload: payload)
    end
  end
end

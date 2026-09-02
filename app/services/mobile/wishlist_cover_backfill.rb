module Mobile
  # Backfills covers for wishlist items that predate cover capture (see
  # docs/MOBILE.md). Two sources, in order:
  #
  #   1. the Goodreads wishlist RSS feed's `book_image_url` — a CDN URL,
  #      but the feed only carries the ~100 most-recently-added items, so
  #      this only helps the tail that was added while sync was running;
  #   2. the ISFDB mirror's `cover_url` for the item's ISBN.
  #
  # The old fallback — scraping each book's Goodreads page for `og:image`
  # — is gone: www.goodreads.com is behind AWS WAF and 202-challenges
  # every scripted request (the CDN cover URLs it *serves* are fine, we
  # just can't get the page to read them from). ISFDB covers download
  # fine and cover ISBN'd items well.
  #
  # Idempotent — skips items that already have a cover — so it's safe to
  # re-run. `ShelfSync#wishlist` captures covers for new items going
  # forward; this is the catch-up.
  class WishlistCoverBackfill
    Result = Struct.new(:attached, :failed, :skipped, keyword_init: true) do
      def to_s = "attached=#{attached} failed=#{failed} skipped=#{skipped}"
    end

    def self.run(**) = new(**).run

    def initialize(feed: nil, client: Isfdb::Client.new)
      feed ||= fetch_wishlist_feed
      @feed_images = feed.to_h { |item| [ item.goodreads_book_id, item.book_image_url ] }
      @client = client
    end

    def run
      result = Result.new(attached: 0, failed: 0, skipped: WishlistItem.count)

      pending.find_each do |item|
        result.skipped -= 1
        url = cover_url_for(item)
        item.attach_cover_from_url(url) if url.present?

        if item.cover_image.attached?
          item.update!(cover_url: url) if item.cover_url.blank?
          result.attached += 1
        else
          result.failed += 1
        end
      end

      result
    end

    private

    def fetch_wishlist_feed
      Goodreads::RssClient.new.fetch("wishlist")
    rescue Goodreads::RssClient::ServiceError => e
      Rails.logger.warn("wishlist cover backfill: RSS feed unavailable (#{e.message}) — ISFDB only")
      []
    end

    def pending
      WishlistItem.where.missing(:cover_image_attachment).where(
        "external_ids ->> 'goodreads' IS NOT NULL " \
        "OR external_ids ->> 'isbn13' IS NOT NULL " \
        "OR external_ids ->> 'isbn10' IS NOT NULL"
      )
    end

    def cover_url_for(item)
      from_feed(item) || from_isfdb(item)
    end

    def from_feed(item)
      @feed_images[item.external_ids["goodreads"]].presence
    end

    def from_isfdb(item)
      isbn = item.external_ids["isbn13"].presence || item.external_ids["isbn10"].presence
      return unless isbn

      @client.lookup_isbn(isbn).filter_map { |c| c["cover_url"].presence }.first
    rescue Isfdb::ServiceError => e
      Rails.logger.warn("wishlist cover backfill: ISFDB lookup failed for #{isbn} — #{e.message}")
      nil
    end
  end
end

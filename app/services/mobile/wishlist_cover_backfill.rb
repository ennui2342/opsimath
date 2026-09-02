require "open-uri"

module Mobile
  # One-time-ish backfill of wishlist covers for the shop-lookup PWA
  # (docs/MOBILE.md). Wishlist items predate cover capture; the RSS feed
  # only carries the ~100 most-recently-added, so the rest come from each
  # book's Goodreads page `og:image`. Idempotent — skips items that
  # already have a cover — so it's safe to re-run. Not scheduled;
  # `ShelfSync#wishlist` covers new items going forward.
  class WishlistCoverBackfill
    Result = Struct.new(:attached, :failed, :skipped, keyword_init: true) do
      def to_s = "attached=#{attached} failed=#{failed} skipped=#{skipped}"
    end

    BOOK_PAGE = "https://www.goodreads.com/book/show/%s"

    def self.run(**) = new(**).run

    # throttle: seconds to pause between Goodreads page fetches (be polite).
    def initialize(feed: nil, throttle: 0.5)
      @throttle = throttle
      feed ||= fetch_wishlist_feed
      @feed_images = feed.to_h { |item| [ item.goodreads_book_id, item.book_image_url ] }
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
      Rails.logger.warn("wishlist cover backfill: RSS feed unavailable (#{e.message}) — Goodreads page scrape only")
      []
    end

    def pending
      WishlistItem.where.missing(:cover_image_attachment)
                  .where("external_ids ->> 'goodreads' IS NOT NULL")
    end

    def cover_url_for(item)
      goodreads_id = item.external_ids["goodreads"]
      @feed_images[goodreads_id].presence || scrape_og_image(goodreads_id)
    end

    def scrape_og_image(goodreads_id)
      sleep @throttle if @throttle.positive?
      html = URI.parse(format(BOOK_PAGE, goodreads_id)).open(read_timeout: 10, &:read)
      url = Nokogiri::HTML(html).at_css('meta[property="og:image"]')&.[]("content")
      url if url.present? && url.exclude?("nophoto")
    rescue StandardError => e
      Rails.logger.warn("wishlist cover scrape failed for goodreads #{goodreads_id}: #{e.message}")
      nil
    end
  end
end

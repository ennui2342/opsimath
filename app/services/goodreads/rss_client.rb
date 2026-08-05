require "net/http"
require "nokogiri"

module Goodreads
  # Fetches and parses one shelf's Goodreads RSS feed — the ongoing-sync
  # counterpart to Phase 1's CSV Importer. See docs/INTEGRATIONS.md's
  # Phase 2 addendum for the real field list this implements, confirmed
  # against the live feed rather than assumed:
  #
  # - capped at 100 items per shelf, no pagination (Goodreads' own limit,
  #   not a bug here)
  # - `isbn` only — no `isbn13` field exists in this feed at all, despite
  #   the original design doc assuming both
  # - no binding/format field at all
  # - `user_date_added` tracks the most recent shelf-transition date (not
  #   `user_date_created`, which is the original first-ever-shelved date —
  #   confirmed against a real to-read -> currently-reading transition)
  class RssClient
    class ServiceError < StandardError; end

    FeedItem = Struct.new(
      :goodreads_book_id, :title, :author_name, :isbn, :num_pages,
      :book_published, :user_rating, :user_read_at, :user_date_added,
      :user_shelves, :user_review, :book_description,
      keyword_init: true
    )

    BASE_URL = "https://www.goodreads.com/review/list_rss/%<user_id>s"

    def initialize(user_id: Rails.application.credentials.dig(:goodreads, :user_id),
                    rss_key: Rails.application.credentials.dig(:goodreads, :rss_key))
      @user_id = user_id
      @rss_key = rss_key
    end

    def fetch(shelf)
      response = get(shelf)
      raise ServiceError, "goodreads rss returned #{response.code} for shelf #{shelf}" unless response.is_a?(Net::HTTPSuccess)

      parse(response.body)
    end

    private

    def get(shelf)
      uri = URI(format(BASE_URL, user_id: @user_id))
      uri.query = URI.encode_www_form(shelf: shelf, key: @rss_key)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end

    def parse(body)
      doc = Nokogiri::XML(body)
      doc.css("item").map { |item| parse_item(item) }
    end

    def parse_item(item)
      FeedItem.new(
        goodreads_book_id: text(item, "book_id"),
        title: text(item, "title"),
        author_name: text(item, "author_name").presence,
        isbn: text(item, "isbn").presence,
        num_pages: text(item, "book/num_pages").presence&.to_i,
        book_published: text(item, "book_published").presence,
        user_rating: RowParser.rating(text(item, "user_rating")),
        user_read_at: parse_rfc2822_date(text(item, "user_read_at")),
        user_date_added: parse_rfc2822_date(text(item, "user_date_added")),
        user_shelves: text(item, "user_shelves").split(",").map(&:strip).reject(&:empty?),
        user_review: text(item, "user_review").presence,
        book_description: text(item, "book_description").presence
      )
    end

    def text(item, xpath)
      item.at_xpath(xpath)&.text.to_s.strip
    end

    def parse_rfc2822_date(raw)
      raw.presence && Time.rfc2822(raw).to_date
    end
  end
end

require "net/http"
require "json"

module OpenLibrary
  class ServiceError < StandardError; end

  # Thin JSON client for openlibrary.org (docs/CATALOG.md, "Providers").
  # Open Library asks API users for a descriptive User-Agent and gentle
  # request rates, so every request — across threads and instances — waits
  # MIN_INTERVAL after the previous one. Follows the redirect an ISBN
  # lookup answers with (/isbn/… -> /books/OL…M.json).
  class Client
    BASE = "https://openlibrary.org".freeze
    USER_AGENT = "opsimath/0.1 (personal book catalogue; https://github.com/ennui2342/opsimath)".freeze
    MIN_INTERVAL = 1.0 # seconds between requests
    PAGE_SIZE = 500
    MAX_EDITIONS = 2000

    @lock = Mutex.new
    @last_request_at = nil
    class << self
      # Blocks until this caller may make the next request.
      def pace(min_interval)
        @lock.synchronize do
          wait = @last_request_at && (@last_request_at + min_interval - Process.clock_gettime(Process::CLOCK_MONOTONIC))
          sleep(wait) if wait&.positive?
          @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end

    def initialize(min_interval: MIN_INTERVAL)
      @min_interval = min_interval
    end

    # Work search: one doc per Open Library work.
    def search(title:, author: nil, limit: 10)
      params = { title:, author:, limit:, fields: "key,title,author_name,first_publish_year,edition_count,cover_i" }.compact
      get_json("/search.json?#{URI.encode_www_form(params)}").fetch("docs", [])
    end

    # The edition record for an ISBN, or nil if Open Library doesn't have it.
    def isbn(isbn) = get_json("/isbn/#{isbn}.json", missing_ok: true)

    # Every edition of a work ("OL…W"), following pagination up to MAX_EDITIONS.
    def editions(work_key)
      path = "/works/#{work_key}/editions.json?limit=#{PAGE_SIZE}"
      entries = []
      while path && entries.size < MAX_EDITIONS
        page = get_json(path, missing_ok: true) or break
        entries.concat(page.fetch("entries", []))
        path = page.dig("links", "next")
      end
      entries
    end

    private

    def get_json(path, missing_ok: false, redirects: 3)
      uri = URI.join(BASE, path)
      self.class.pace(@min_interval)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) { |h| h.request(request) }
      case response
      when Net::HTTPSuccess then JSON.parse(response.body)
      when Net::HTTPRedirection
        raise ServiceError, "too many redirects for #{path}" if redirects.zero?

        get_json(URI(response["location"]).request_uri, missing_ok:, redirects: redirects - 1)
      when Net::HTTPNotFound
        raise ServiceError, "openlibrary returned 404 for #{path}" unless missing_ok
      else
        raise ServiceError, "openlibrary returned #{response.code} for #{path}"
      end
    end
  end
end

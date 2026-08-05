require "net/http"
require "json"

module Isfdb
  # Thin JSON client for ~/projects/isfdb-adapter — see that repo's README
  # for the full API contract. Only /isbn/{isbn} is used so far (per
  # docs/INTEGRATIONS.md's enrichment scope: ISBN-based lookup only for
  # v1, /search's fuzzy title/author matching deliberately deferred).
  class ServiceError < StandardError; end

  class Client
    def initialize(base_url: ENV.fetch("ISFDB_ADAPTER_URL"))
      @base_url = base_url
    end

    # Returns the parsed response hash, or nil if this ISBN isn't in the
    # mirror (404 — a real, expected outcome, not an error: ISFDB's
    # coverage is real but incomplete, especially for small-press and
    # very recent editions).
    def lookup_isbn(isbn)
      response = get("/isbn/#{isbn}")
      return nil if response.is_a?(Net::HTTPNotFound)

      raise ServiceError, "isfdb-adapter returned #{response.code} for isbn #{isbn}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    private

    def get(path)
      uri = URI.join(@base_url, path)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end
  end
end

require "net/http"
require "json"

module Ebay
  class Error < StandardError; end

  # Thin client for eBay's Browse API — active listings only, read-only
  # (docs/BARGAIN_HUNTING.md). Application-only OAuth (client credentials):
  # no eBay user is involved. The token lasts ~2h and is held for the life
  # of the client, so one client per sweep is one token request.
  #
  # Every price comes back in GBP for the EBAY_GB marketplace — eBay
  # converts foreign listings and keeps the original alongside.
  class Client
    API = "https://api.ebay.com".freeze
    SCOPE = "https://api.ebay.com/oauth/api_scope".freeze
    MARKETPLACE = "EBAY_GB".freeze

    def initialize(client_id: Rails.application.credentials.dig(:ebay, :client_id),
                   client_secret: Rails.application.credentials.dig(:ebay, :client_secret))
      @client_id = client_id
      @client_secret = client_secret
    end

    # Item summaries for a search, at most `limit` (one page). Pass `q:`
    # (keywords) or `gtin:` (an ISBN), plus any of eBay's own params
    # (filter:, sort:, category_ids:). [] when nothing matches.
    def search(limit: 50, **params)
      get("/buy/browse/v1/item_summary/search", params.merge(limit:))["itemSummaries"] || []
    end

    # Full detail for one listing (localizedAspects: ISBN, Publisher,
    # Publication Year, Format…). nil when it has ended or vanished.
    def item(item_id)
      get("/buy/browse/v1/item/#{ERB::Util.url_encode(item_id)}")
    rescue Error => e
      raise unless e.message.start_with?("404")

      nil
    end

    private

    def get(path, params = {})
      uri = URI.join(API, path)
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["X-EBAY-C-MARKETPLACE-ID"] = MARKETPLACE
      response = http(uri) { |h| h.request(request) }
      raise Error, "#{response.code} from eBay #{path}: #{response.body.to_s[0, 300]}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def token
      return @token if @token && Time.current < @token_expires_at

      raise Error, "no eBay credentials (credentials ebay.client_id / client_secret)" if @client_id.blank? || @client_secret.blank?

      uri = URI.join(API, "/identity/v1/oauth2/token")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(@client_id, @client_secret)
      request.set_form_data("grant_type" => "client_credentials", "scope" => SCOPE)
      response = http(uri) { |h| h.request(request) }
      raise Error, "#{response.code} from eBay token endpoint" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      @token_expires_at = Time.current + body["expires_in"].to_i.seconds - 5.minutes
      @token = body["access_token"]
    end

    def http(uri, &)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20, &)
    end
  end
end

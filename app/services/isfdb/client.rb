require "net/http"
require "json"

module Isfdb
  # Thin JSON client for ~/projects/isfdb-adapter — see that repo's README
  # for the full API contract. ISBN-keyed lookups only (per
  # docs/INTEGRATIONS.md's enrichment scope: /search's fuzzy title/author
  # matching deliberately deferred).
  class ServiceError < StandardError; end

  class Client
    def initialize(base_url: ENV.fetch("ISFDB_ADAPTER_URL"))
      @base_url = base_url
    end

    # Returns every ISFDB publication matching this ISBN, most recent
    # printing first — empty array if this ISBN isn't in the mirror at
    # all (404 — a real, expected outcome, not an error: ISFDB's coverage
    # is real but incomplete, especially for small-press and very recent
    # editions). An ISBN isn't always unique to one specific printing
    # (confirmed 2026-08-10: 565 of 1,493 of opsimath's own ISFDB-matched
    # ISBNs hit this, skewed high by how often vintage mass-market SF
    # gets reprinted under the same ISBN) — `?all=true` returns every
    # candidate rather than isfdb-adapter's own single-result default
    # (which just picks the most recent), so the caller can pick the
    # printing that actually matches other evidence already on file
    # rather than blindly trusting "newest wins." See
    # Enrichment::IsfdbEditionEnricher#best_candidate.
    def lookup_isbn(isbn)
      response = get("/isbn/#{isbn}?all=true")
      return [] if response.is_a?(Net::HTTPNotFound)

      raise ServiceError, "isfdb-adapter returned #{response.code} for isbn #{isbn}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    # Every publication ISFDB holds for the *title* this ISBN belongs to —
    # i.e. all the other printings (hardcover, mass market, book club,
    # ebook) of the same book. Edition-shaped records, same fields as
    # lookup_isbn. `[]` when the ISBN isn't in the mirror (404). Used to
    # widen the mobile snapshot's ISBN index (Mobile::SnapshotBuilder) so
    # scanning any printing resolves to a work you own, and it's the
    # natural backing for a future "switch edition" picker in the web app.
    def lookup_editions(isbn)
      response = get("/isbn/#{isbn}/editions")
      return [] if response.is_a?(Net::HTTPNotFound)

      raise ServiceError, "isfdb-adapter returned #{response.code} for isbn #{isbn} editions" unless response.is_a?(Net::HTTPSuccess)

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

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
    #
    # A long-lived title's list is big (The Lord of the Rings: ~240
    # printings) and the adapter assembles each one, so this call gets a
    # longer timeout than the single-edition lookups.
    # A publisher's line (ISFDB publication series) and every printing in
    # it, in number order: { "id", "name", "publications" => [...] }. nil
    # when there's no such line, or the mirror hasn't imported line names
    # yet (isfdb-adapter answers 503 until it has).
    def publication_series(id)
      response = get("/pubseries/#{Integer(id)}", read_timeout: 60)
      return nil if response.is_a?(Net::HTTPNotFound) || response.is_a?(Net::HTTPServiceUnavailable)

      raise ServiceError, "isfdb-adapter returned #{response.code} for publication series #{id}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def lookup_editions(isbn)
      response = get("/isbn/#{isbn}/editions", read_timeout: 30)
      return [] if response.is_a?(Net::HTTPNotFound)

      raise ServiceError, "isfdb-adapter returned #{response.code} for isbn #{isbn} editions" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    # isfdb-adapter's freetext /search — title and author words matched
    # separately, every edition of each matched title (up to
    # editions_per_title), in the /isbn shape. [] when nothing matches.
    # `limit` counts rows (printings), not titles — a title with many
    # printings can crowd the rest out, so callers wanting breadth raise it.
    def search(query, limit: 60, editions_per_title: 30)
      response = get("/search?#{URI.encode_www_form(q: query, limit:, editions_per_title:)}", read_timeout: 30)
      raise ServiceError, "isfdb-adapter returned #{response.code} for search" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    # ISFDB authors whose canonical name contains `name` (a substring
    # match, so the caller picks the exact one). [] when none.
    def search_authors(name, limit: 200)
      response = get("/authors/search?#{URI.encode_www_form(q: name, limit:)}")
      raise ServiceError, "isfdb-adapter returned #{response.code} for author search" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    # One author's profile (born_date / died_date / …) without the
    # bibliography (`works=false` — building it costs ~27s for a prolific
    # author). The long timeout covers an adapter that predates
    # works=false and builds it anyway. nil if ISFDB has no such author.
    def author(author_id)
      response = get("/authors/#{author_id}?works=false", read_timeout: 60)
      return nil if response.is_a?(Net::HTTPNotFound)

      raise ServiceError, "isfdb-adapter returned #{response.code} for author #{author_id}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    private

    def get(path, read_timeout: 10)
      uri = URI.join(@base_url, path)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout:) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end
  end
end

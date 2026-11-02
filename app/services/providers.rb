# The metadata provider registry (docs/CATALOG.md, "Providers"): each
# provider declares what it can do, and callers ask the registry for the
# providers with a capability rather than naming one. The idea is
# librarium's (librarium-api/internal/providers/); unlike librarium's,
# results here stay grouped by work and are never merged across
# providers — a provider's record is kept as it came, and fields are
# chosen into the catalogue later by the enrichment machinery.
#
# Capabilities:
#   :known_editions  every edition the provider knows for a catalogued
#                    work, found via the work's ISBNs or a provider work id
#   :search_works    title + author search, one result per provider work
module Providers
  # One edition as a provider knows it — the shape ProviderEdition stores.
  Edition = Struct.new(:provider, :id, :work_id, :title, :isbn13, :isbn10, :publisher, :binding,
                       :publish_date, :language, :page_count, :cover_url, :cover_artist, keyword_init: true) do
    def isbn = isbn13.presence || (isbn10.presence && Isbn.to_13(isbn10))
  end

  # One work in a search result, with whatever editions came with it.
  Work = Struct.new(:provider, :id, :title, :authors, :first_year, :cover_url, :edition_count, :editions,
                    keyword_init: true)

  # What a provider knows for one catalogued work: the provider's id(s) for
  # the work itself, and its editions.
  KnownEditions = Struct.new(:work_ids, :editions, keyword_init: true)

  REGISTRY = %w[Providers::Isfdb Providers::OpenLibrary].freeze
  SEARCH_TIMEOUT = 20.seconds

  def self.all = REGISTRY.map { |name| name.constantize.new }

  def self.find(name) = all.find { |p| p.name == name.to_s } || raise(ArgumentError, "unknown provider #{name}")

  def self.with(capability) = all.select { |p| p.capabilities.include?(capability) }

  # Every provider's works for a title + author, searched in parallel. A
  # provider that fails or runs over the time limit contributes nothing
  # rather than failing the search.
  def self.search_works(title:, author: nil, providers: with(:search_works))
    threads = providers.map do |provider|
      Thread.new do
        provider.search_works(title:, author:)
      rescue StandardError => e
        Rails.logger.warn("provider search: #{provider.name} — #{e.class}: #{e.message}")
        []
      end
    end
    deadline = SEARCH_TIMEOUT.from_now
    threads.flat_map do |t|
      t.join([ deadline - Time.current, 0 ].max) ? t.value : (t.kill && [])
    end
  end
end

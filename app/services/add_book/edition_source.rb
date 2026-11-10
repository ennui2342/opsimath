module AddBook
  # The provider editions an edition picker chooses between. A catalogued
  # work reads its known editions (provider_editions, no network) —
  # fetched live only if it has none yet; a search result's are fetched
  # from each provider. A provider that fails contributes nothing.
  module EditionSource
    def self.for_work(work)
      return EditionCards.from_provider_editions(work.provider_editions) if work.provider_editions.any?

      fetch(provider_works(work)).presence || by_title(work)
    end

    # A book with no links yet (a Goodreads-imported edition with no ISBN:
    # The Syndic, 2026-11-10): its printings found live by title and author,
    # the matching rule the nightly lookup uses (WorkMatcher), so "Add
    # another edition" / "Choose the right printing" have something to offer.
    def self.by_title(work)
      author = work.authors.first&.name
      Providers.with(:search_works).flat_map do |provider|
        matches = WorkMatcher.match(provider.search_works(title: WorkMatcher.plain(work.title), author:, complete: true), title: work.title, author:)
        editions = matches.flat_map { |m| Array(m.editions) }
        editions = matches.flat_map { |m| provider.known_editions(isbns: [], work_ids: [ m.id ]).editions } if editions.empty?
        editions
      rescue StandardError => e
        Rails.logger.warn("edition picker: #{provider.name} title search — #{e.class}: #{e.message}")
        []
      end
    end

    def self.for_found(found) = fetch(found["provider_works"])

    # A catalogued work as provider works: ISFDB by the ISBNs it's known by
    # (its editions' and its want's), Open Library by each stored work id —
    # it can hold several for one book (its duplicate works).
    def self.provider_works(work)
      isbns = work.editions.flat_map(&:edition_identifiers).select { |i| i.id_type.start_with?("isbn") }.map(&:value) +
              Array(work.want&.seed_isbns)
      ol_ids = work.work_identifiers.select { |i| i.id_type == "openlibrary_work" }.map(&:value)
      [ { "provider" => "isfdb", "isbns" => isbns } ] + ol_ids.map { |id| { "provider" => "openlibrary", "id" => id } }
    end

    def self.fetch(provider_works)
      Array(provider_works).flat_map do |pw|
        case pw["provider"]
        when "isfdb"
          isbn = Array(pw["isbns"]).first
          isbn ? Providers::Isfdb.new.editions_for_isbn(isbn) : Array(pw["editions"]).map { |e| Providers::Edition.new(**e.symbolize_keys) }
        when "openlibrary"
          pw["id"].present? ? Providers::OpenLibrary.new.editions(pw["id"]) : []
        else []
        end
      rescue StandardError => e
        Rails.logger.warn("edition picker: #{pw["provider"]} editions — #{e.class}: #{e.message}")
        []
      end
    end
  end
end

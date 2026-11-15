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
    # Searched the way Add a book searches (its apostrophe and number forms,
    # AddBook::Search.variants), with the author and then — when an
    # author's other books crowd the results — without (The Year's Best
    # Science Fiction 2, among Aldiss's own collections), stopping at the
    # first search that finds the book. A quick search finds it; only the
    # match's printings are then fetched in full. The providers are asked
    # side by side, and the page gets whatever is back within DEADLINE: a
    # book ISFDB doesn't have (The Wealth of Nations) ran every search there
    # while Open Library was down, and the page timed out (2026-11-15).
    DEADLINE = 20 # seconds

    def self.by_title(work, deadline: DEADLINE, providers: Providers.with(:search_works))
      author = work.authors.first&.name
      queries = AddBook::Search.variants(WorkMatcher.plain(work.title))
      # The title as written first, with the author and without; then its
      # other forms.
      attempts = queries.flat_map { |q| [ author, nil ].uniq.map { |a| [ q, a ] } }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      futures = providers.map do |provider|
        Concurrent::Promises.future do
          Rails.application.executor.wrap { printings_by_title(provider, work, author, attempts, started + deadline) }
        end
      end
      futures.flat_map { |f| f.value(deadline) || [] }
    end

    def self.printings_by_title(provider, work, author, attempts, give_up_at)
      matches = attempts.lazy.take_while { Process.clock_gettime(Process::CLOCK_MONOTONIC) < give_up_at }
                        .map { |q, a| WorkMatcher.match(provider.search_works(title: q, author: a), title: work.title, author:) }
                        .find(&:any?) || []
      matches.flat_map { |m| provider.known_editions(isbns: [], work_ids: [ m.id ]).editions }
    rescue StandardError => e
      Rails.logger.warn("edition picker: #{provider.name} title search — #{e.class}: #{e.message}")
      []
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

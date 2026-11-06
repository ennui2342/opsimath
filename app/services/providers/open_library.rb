module Providers
  # Open Library (OpenLibrary::Client): open data, natively work -> editions,
  # and the second provider for non-SF books and many SF ones ISFDB's ISBN
  # lookup misses (docs/CATALOG.md, "The coverage probe"). Editions are
  # often missing a format (physical_format, kept as given) and include
  # translations (language kept, so the edition picker can prefer English).
  class OpenLibrary
    WORK_ID_TYPE = "openlibrary_work".freeze
    COVER_URL = "https://covers.openlibrary.org/b/id/%d-L.jpg".freeze # by cover id: not rate limited, unlike ISBN-keyed cover URLs
    ISBN_ATTEMPTS = 3 # each miss is a request

    def initialize(client: ::OpenLibrary::Client.new)
      @client = client
    end

    def name = "openlibrary"

    def capabilities = %i[known_editions search_works]

    # The work's Open Library editions: its work key from a previous run, or
    # found from the work's own ISBNs (an edition record names its work).
    #
    # Open Library keeps duplicate works for one book (Lord of Light: three),
    # so a book can hold several stored work ids — each one's editions are
    # fetched, up to MAX_WORKS.
    MAX_WORKS = 4

    def known_editions(isbns:, work_ids: [])
      keys = work_ids.first(MAX_WORKS).presence ||
             [ isbns.first(ISBN_ATTEMPTS).lazy.filter_map { |i| @client.isbn(i)&.dig("works", 0, "key")&.delete_prefix("/works/") }.first ].compact
      return KnownEditions.new(work_ids: [], editions: []) if keys.empty?

      KnownEditions.new(work_ids: keys, editions: keys.flat_map { |key| editions(key) }.uniq(&:id))
    end

    # One result per Open Library work; editions are fetched once a work is
    # chosen (editions(work_id)) — a search lists works, not printings.
    # Open Library often has several works for one book (Crossfire: three).
    # `title:` alone is sent as free text — the add-a-book box takes title
    # and author words together, as typed.
    def search_works(title:, author: nil, complete: false)
      docs = author ? @client.search(title:, author:, limit: complete ? 20 : 10) : @client.search(q: title)
      docs.map do |doc|
        Work.new(provider: name, id: doc["key"].to_s.delete_prefix("/works/"), title: doc["title"],
                 authors: Array(doc["author_name"]), first_year: doc["first_publish_year"],
                 cover_url: doc["cover_i"].to_i.positive? ? format(COVER_URL, doc["cover_i"]) : nil,
                 edition_count: doc["edition_count"], editions: nil, languages: Array(doc["language"]))
      end
    end

    # Open Library's search takes an ISBN as free text and answers with the
    # work — with its authors, which the plain ISBN endpoint doesn't carry.
    def works_for_isbn(isbn) = search_works(title: isbn)

    def editions(work_key) = @client.editions(work_key).filter_map { |ed| edition(ed, work_key) }

    private

    def edition(ed, work_key)
      key = ed["key"].to_s.delete_prefix("/books/")
      return if key.blank?

      cover = Array(ed["covers"]).find { |c| c.to_i.positive? }
      Edition.new(
        provider: name, id: key, work_id: work_key,
        title: [ ed["title"], ed["subtitle"] ].compact_blank.join(": ").presence,
        isbn13: Array(ed["isbn_13"]).first.presence, isbn10: Array(ed["isbn_10"]).first.presence,
        publisher: Array(ed["publishers"]).first.presence, binding: ed["physical_format"].presence,
        publish_date: Edtf.from_text(ed["publish_date"]), language: Array(ed["languages"]).first&.dig("key")&.delete_prefix("/languages/"),
        page_count: ed["number_of_pages"], cover_url: cover && format(COVER_URL, cover), cover_artist: nil
      )
    end
  end
end

module Providers
  # ISFDB, via isfdb-adapter (Isfdb::Client). Best for SF: bindings, cover
  # artists, every printing.
  class Isfdb
    WORK_ID_TYPE = "isfdb_title".freeze

    def initialize(client: ::Isfdb::Client.new)
      @client = client
    end

    def name = "isfdb"

    def capabilities = %i[known_editions search_works]

    # Every publication ISFDB lists for the title(s) the work's ISBNs belong
    # to — the first ISBN that resolves wins, as every printing's ISBN
    # resolves to the same title. The list also holds each omnibus or
    # collection containing the work, each reporting its own main title, so
    # the work's own title id is taken only from its own printings.
    #
    # An anthology, nonfiction book or magazine has no printing list:
    # isfdb-adapter only builds those for book-type titles ("isbn found but
    # not linked to a book-type title"). Its own publication still comes
    # back from a plain ISBN lookup, so that one printing is taken — enough
    # for the edition's anchor (AnchoredRefresh); its siblings stay unknown.
    OWN_LOOKUPS = 2

    def known_editions(isbns:, work_ids: [])
      raw = isbns.any? ? ::Isfdb::WorkEditions.for(nil, client: @client, isbns:) : []
      raw = isbns.first(OWN_LOOKUPS).lazy.map { |isbn| @client.lookup_isbn(isbn) }.find(&:any?) || [] if raw.empty? && isbns.any?
      own = isbns.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact

      editions = raw.filter_map { |ed| edition(ed) }
      title_ids = raw.select { |ed| own.include?(isbn_of(ed)) }.filter_map { |ed| ed["_isfdb_title_id"].presence&.to_s }.uniq
      KnownEditions.new(work_ids: title_ids, editions:)
    end

    # isfdb-adapter's /search: title and author words matched separately,
    # then every edition of each matched title — grouped back into works.
    #
    # `complete: true` (identifying a book, not browsing): up to 500 rows
    # with every printing per title — the limit counts rows, not titles,
    # and at 60 The Dragon in the Sea was cut off entirely.
    def search_works(title:, author: nil, complete: false)
      query = [ title, author ].compact.join(" ")
      works_from(complete ? @client.search(query, limit: 500, editions_per_title: 200) : @client.search(query, limit: 300))
    end

    # The work(s) an ISBN belongs to, with the printings under that ISBN.
    def works_for_isbn(isbn) = works_from(@client.lookup_isbn(isbn))

    # Every ISFDB publication of the title an ISBN belongs to (and of any
    # omnibus containing it) — the full edition list for the picker.
    def editions_for_isbn(isbn) = @client.lookup_editions(isbn).filter_map { |ed| edition(ed) }

    # One isfdb-adapter publication hash as a provider edition (an
    # enrichment_printing_choice decision stores them raw).
    def edition_from(raw) = edition(raw)

    private

    def works_from(raw)
      raw.group_by { |ed| ed["_isfdb_title_id"] }.filter_map do |title_id, eds|
        next if title_id.blank?

        editions = eds.filter_map { |ed| edition(ed) }
        Work.new(provider: name, id: title_id.to_s, title: eds.first["title"], authors: Array(eds.first["authors"]),
                 first_year: editions.filter_map { |e| e.publish_date.to_s[/\A\d{4}/]&.to_i }.min,
                 cover_url: editions.filter_map(&:cover_url).first, edition_count: editions.size, editions:,
                 languages: editions.filter_map(&:language).uniq)
      end
    end

    def isbn_of(ed) = ed["isbn_13"].presence || (ed["isbn_10"].presence && Isbn.to_13(ed["isbn_10"]))

    def edition(ed)
      return if ed["_isfdb_pub_id"].blank?

      Edition.new(
        provider: name, id: ed["_isfdb_pub_id"].to_s, work_id: ed["_isfdb_title_id"].presence&.to_s,
        title: ed["title"].presence, isbn13: ed["isbn_13"].presence, isbn10: ed["isbn_10"].presence,
        publisher: ed["publisher"].presence, binding: ed["binding"].presence, publish_date: ed["publish_date"].presence,
        language: ed["language"].presence, page_count: ed["page_count"],
        cover_url: ed["cover_url"].to_s.split("|").first.presence, # ISFDB sometimes holds "url|url"
        cover_artist: Array(ed["cover_artists"]).join(", ").presence,
        pub_series_id: ed["_isfdb_pub_series_id"].presence&.to_i, pub_series_name: ed["pub_series"].presence,
        pub_series_num: ed["pub_series_num"].presence,
        series_id: ed["_isfdb_series_id"].presence&.to_i, series_name: ed["series"].presence,
        series_num: ed["_isfdb_series_num"].presence&.then { |n| n.to_d.nonzero? } # 0: in the series, unnumbered
      )
    end
  end
end

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
    def known_editions(isbns:, work_ids: [])
      raw = ::Isfdb::WorkEditions.for(nil, client: @client, isbns:)
      own = isbns.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact
      editions = raw.filter_map { |ed| edition(ed) }
      title_ids = raw.select { |ed| own.include?(isbn_of(ed)) }.filter_map { |ed| ed["_isfdb_title_id"].presence&.to_s }.uniq
      KnownEditions.new(work_ids: title_ids, editions:)
    end

    # isfdb-adapter's /search: title and author words matched separately,
    # then every edition of each matched title — grouped back into works.
    def search_works(title:, author: nil)
      @client.search([ title, author ].compact.join(" ")).group_by { |ed| ed["_isfdb_title_id"] }.filter_map do |title_id, eds|
        next if title_id.blank?

        editions = eds.filter_map { |ed| edition(ed) }
        Work.new(provider: name, id: title_id.to_s, title: eds.first["title"], authors: Array(eds.first["authors"]),
                 first_year: editions.filter_map { |e| e.publish_date.to_s[/\A\d{4}/]&.to_i }.min,
                 cover_url: editions.filter_map(&:cover_url).first, edition_count: editions.size, editions:)
      end
    end

    private

    def isbn_of(ed) = ed["isbn_13"].presence || (ed["isbn_10"].presence && Isbn.to_13(ed["isbn_10"]))

    def edition(ed)
      return if ed["_isfdb_pub_id"].blank?

      Edition.new(
        provider: name, id: ed["_isfdb_pub_id"].to_s, work_id: ed["_isfdb_title_id"].presence&.to_s,
        title: ed["title"].presence, isbn13: ed["isbn_13"].presence, isbn10: ed["isbn_10"].presence,
        publisher: ed["publisher"].presence, binding: ed["binding"].presence, publish_date: ed["publish_date"].presence,
        language: ed["language"].presence, page_count: ed["page_count"],
        cover_url: ed["cover_url"].to_s.split("|").first.presence, # ISFDB sometimes holds "url|url"
        cover_artist: Array(ed["cover_artists"]).join(", ").presence
      )
    end
  end
end

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
    # A work with no ISBN that resolves (an ISBN-less edition, a want with
    # none) falls back to a title + author search: the one ISFDB title whose
    # title and author match the work's — never a guess among several — with
    # the printings the search lists for it.
    def known_editions(isbns:, work_ids: [], title: nil, author: nil)
      raw = isbns.any? ? ::Isfdb::WorkEditions.for(nil, client: @client, isbns:) : []
      own = isbns.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact
      return by_title(title, author, work_ids) if raw.empty? && title.present?

      editions = raw.filter_map { |ed| edition(ed) }
      title_ids = raw.select { |ed| own.include?(isbn_of(ed)) }.filter_map { |ed| ed["_isfdb_title_id"].presence&.to_s }.uniq
      KnownEditions.new(work_ids: title_ids, editions:)
    end

    # isfdb-adapter's /search: title and author words matched separately,
    # then every edition of each matched title — grouped back into works.
    def search_works(title:, author: nil)
      works_from(@client.search([ title, author ].compact.join(" "), limit: 300))
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

    # The work's ISFDB title by title + author. ISFDB often holds several
    # records under one title and author — translations that kept the
    # title (German "Lexicon"), adaptations ("Kindred: A Graphic Novel
    # Adaptation"), the same book credited two ways (Brian / Brian M.
    # Stableford's "The Paradise Game") — so: drop records with no English
    # printing, prefer an exact full-title match, and take identical
    # English records together as one book. Anything still ambiguous
    # (The Past Through Tomorrow "Vol. 2" against "Vol. 1" and "Book One")
    # takes nothing.
    SEARCH_ROWS = 500 # rows, not titles: 60 cut The Dragon in the Sea off entirely

    def by_title(title, author, work_ids)
      surname = fold(author).split.last
      groups = @client.search([ title, author ].compact.join(" "), limit: SEARCH_ROWS, editions_per_title: 200)
                      .group_by { |ed| ed["_isfdb_title_id"].to_s }.reject { |id, _| id.blank? }
      candidates =
        if work_ids.any? then groups.slice(*work_ids)
        else
          groups.select do |_, eds|
            fold(short(eds.first["title"])) == fold(short(title)) &&
              (surname.nil? || Array(eds.first["authors"]).any? { |a| fold(a).split.last == surname }) &&
              eds.any? { |ed| ENGLISH.include?(ed["language"].to_s.downcase) }
          end
        end
      exact = candidates.select { |_, eds| fold(eds.first["title"]) == fold(title) }
      candidates = exact if exact.any?
      return KnownEditions.new(work_ids: [], editions: []) unless candidates.size == 1 || (candidates.size > 1 && exact.size == candidates.size)

      # The search's own printings of the title(s) — exactly its editions
      # (an ISBN lookup from one of them can wander into the series:
      # Calder's Dead Boys pulled in Dead Girls and Dead Things).
      KnownEditions.new(work_ids: candidates.keys, editions: candidates.values.flatten.filter_map { |ed| edition(ed) }.uniq(&:id))
    end

    ENGLISH = [ "", "eng", "en", "english" ].freeze

    def short(text) = text.to_s.split(/[:(]/).first.to_s

    def fold(text) = I18n.transliterate(text.to_s.tr("’‘", "''")).downcase.delete("'").gsub(/[^a-z0-9]+/, " ").strip

    def works_from(raw)
      raw.group_by { |ed| ed["_isfdb_title_id"] }.filter_map do |title_id, eds|
        next if title_id.blank?

        editions = eds.filter_map { |ed| edition(ed) }
        Work.new(provider: name, id: title_id.to_s, title: eds.first["title"], authors: Array(eds.first["authors"]),
                 first_year: editions.filter_map { |e| e.publish_date.to_s[/\A\d{4}/]&.to_i }.min,
                 cover_url: editions.filter_map(&:cover_url).first, edition_count: editions.size, editions:)
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
        cover_artist: Array(ed["cover_artists"]).join(", ").presence
      )
    end
  end
end

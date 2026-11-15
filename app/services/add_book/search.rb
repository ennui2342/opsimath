module AddBook
  # Step 0 of adding a book (docs/CATALOG.md, "The two-step model"): find
  # the work. Every provider is searched at once (Providers.search_works);
  # their works are grouped into one result per book — same short title
  # and author surname — carrying every provider's record, nothing merged.
  # A result already in the catalogue says so: by a stored provider work
  # id first (WorkIdentifier), else by title and author.
  #
  # An ISBN typed into the box is looked up instead, in every provider
  # that knows ISBNs, and its work found from there.
  #
  # Ranked by how well the title and author match what was typed — the
  # providers' own matching is loose (isfdb-adapter matches any title or
  # author word: "hackers steven levy" brings back Steven Spielberg) — and
  # cut to the best MAX_RESULTS. ISFDB title records whose known editions
  # are all in other languages (a novel's translations are separate
  # titles there) are left out.
  class Search
    Result = Struct.new(:title, :authors, :first_year, :cover_url, :provider_works, :work, keyword_init: true) do
      def providers = provider_works.map(&:provider).uniq

      def edition_count = provider_works.sum { |w| w.edition_count.to_i }

      # What the next request needs, compactly (it travels signed): each
      # provider work with a few of its ISBNs — enough to fetch its full
      # edition list — or, for an ISFDB title with no ISBN'd printing,
      # those printings themselves (they can't be looked up again).
      def to_payload
        {
          "title" => title, "authors" => authors, "first_year" => first_year, "cover_url" => cover_url,
          "provider_works" => provider_works.map do |w|
            isbns = Array(w.editions).filter_map(&:isbn).uniq.first(5)
            { "provider" => w.provider, "id" => w.id, "isbns" => isbns,
              "editions" => (isbns.empty? ? Array(w.editions).first(30).map(&:to_h) : []) }
          end
        }
      end
    end

    WORK_ID_TYPES = { "isfdb" => "isfdb_title", "openlibrary" => "openlibrary_work" }.freeze
    MAX_RESULTS = 15

    def self.run(query, **) = new(**).run(query)

    def initialize(providers: Providers.with(:search_works))
      @providers = providers
    end

    def run(query)
      query = query.to_s.strip
      return [] if query.length < 2

      if (upc = UpcLookup.parse(query))
        return group(upc_isbns(*upc).flat_map { |i| isbn_works(i) }.reject { |w| foreign_only?(w) })
      end

      isbn = Isbn.normalize(query)
      works = isbn ? isbn_works(isbn) : search(query)
      results = group(works.reject { |w| foreign_only?(w) })
      isbn ? results : rank(results, query).first(MAX_RESULTS)
    end

    private

    # The words as typed, and the forms ISFDB's word search would otherwise
    # miss: a possessive typed without its apostrophe ("years" for
    # "year's" — "Harrison years best" never found The Year's Best Science
    # Fiction No. 1), and a number as digits or words ("best 2" / "best
    # two" — anthologies vary, Mark, 2026-11-15).
    def search(query)
      self.class.variants(query)
          .flat_map { |q| Providers.search_works(title: q, providers: @providers) }
          .uniq { |w| [ w.provider, w.id ] }
    end

    NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
                      sixteen seventeen eighteen nineteen twenty].freeze
    # II–XX: a lone "I" is more often the word than the numeral (I, Robot).
    ROMAN = %w[ii iii iv v vi vii viii ix x xi xii xiii xiv xv xvi xvii xviii xix xx].each_with_index.to_h { |r, i| [ r, i + 2 ] }.freeze

    def self.variants(query)
      base = [ query, apostrophised(query) ].compact.uniq
      (base + base.flat_map { |q| [ numbers_as(q, :words), numbers_as(q, :digits) ] }).compact.uniq
    end

    # The query with its numbers as words ("2" → "two") or as digits
    # ("two", "II" → "2"); nil when there are none to change.
    def self.numbers_as(query, form)
      alt = query.gsub(/[[:alnum:]]+/) do |word|
        down = word.downcase
        if form == :words && word.match?(/\A\d+\z/) && word.to_i <= 20 then NUMBER_WORDS[word.to_i]
        elsif form == :digits && (n = NUMBER_WORDS.index(down) || (word.size > 1 && ROMAN[down])) then n.to_s
        else word
        end
      end
      alt == query ? nil : alt
    end

    def self.apostrophised(query)
      alt = query.gsub(/\b([A-Za-z]{3,}[^s'’])s\b/) { "#{Regexp.last_match(1)}'s" }
      alt == query ? nil : alt
    end

    # A US mass-market's UPC + add-on: its candidate ISBNs (UpcLookup).
    def upc_isbns(upc, add_on)
      UpcLookup.call(upc:, add_on:).isbns.first(MAX_RESULTS)
    rescue StandardError => e
      Rails.logger.warn("add book: UPC #{upc} #{add_on} — #{e.class}: #{e.message}")
      []
    end

    def isbn_works(isbn)
      @providers.flat_map do |provider|
        provider.respond_to?(:works_for_isbn) ? provider.works_for_isbn(isbn) : []
      rescue StandardError => e
        Rails.logger.warn("add book: #{provider.name} ISBN #{isbn} — #{e.class}: #{e.message}")
        []
      end
    end

    ENGLISH = AddBook::EditionCards::ENGLISH

    def foreign_only?(work)
      eds = Array(work.editions)
      work.provider == "isfdb" && eds.any? && eds.none? { |e| ENGLISH.include?(e.language.to_s.downcase) }
    end

    # Title words found count double, author words once; a book both
    # providers know edges ahead; then the order the providers gave.
    def rank(results, query)
      words = fold(query).split
      results.each_with_index.sort_by do |r, i|
        title = " #{fold(r.title)} "
        authors = " #{fold(r.authors.join(' '))} "
        score = words.sum { |w| (title.include?(" #{w} ") ? 2 : 0) + (authors.include?(" #{w} ") ? 1 : 0) }
        [ -score, -r.providers.size, i ]
      end.map(&:first)
    end

    def group(works)
      works.group_by { |w| [ fold(short(w.title)), fold(Array(w.authors).first.to_s).split.last ] }.map do |_, group|
        Result.new(
          title: group.first.title, authors: group.flat_map { |w| Array(w.authors) }.uniq { |a| fold(a) }.first(3),
          first_year: group.filter_map(&:first_year).min, cover_url: group.filter_map(&:cover_url).first,
          provider_works: group, work: catalogue_work(group)
        )
      end
    end

    def catalogue_work(group)
      by_id = group.lazy.filter_map do |w|
        WorkIdentifier.find_by(id_type: WORK_ID_TYPES[w.provider], value: w.id)&.work
      end.first
      return by_id if by_id

      title = fold(short(group.first.title))
      surname = fold(Array(group.first.authors).first.to_s).split.last
      Work.includes(work_contributors: :contributor).where("lower(title) LIKE ?", "#{title.split.first}%").find do |work|
        fold(short(work.title)) == title && work.authors.any? { |a| fold(a.name).split.last == surname }
      end
    end

    def short(title) = title.to_s.split(/[:(]/).first.to_s

    # Apostrophes dropped, not spaced ("Year's" is "years", as typed), and
    # numbers as digits ("Two", "II" are "2").
    def fold(text)
      words = I18n.transliterate(text.to_s).downcase.gsub(/['’]/, "").gsub(/[^a-z0-9]+/, " ").split
      words.map { |w| (n = NUMBER_WORDS.index(w) || (w.size > 1 && ROMAN[w])) ? n.to_s : w }.join(" ")
    end
  end
end

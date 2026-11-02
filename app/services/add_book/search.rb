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

      isbn = Isbn.normalize(query)
      works = isbn ? isbn_works(isbn) : Providers.search_works(title: query, providers: @providers)
      results = group(works.reject { |w| foreign_only?(w) })
      isbn ? results : rank(results, query).first(MAX_RESULTS)
    end

    private

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

    def fold(text) = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end

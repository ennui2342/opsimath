module AddBook
  # Step 1 of adding a book (docs/CATALOG.md, "The two-step model"): the
  # work's editions from every provider, one card per publisher + cover —
  # the way Mark chooses his edition. Nothing is merged: a card is a
  # bundle of provider records.
  #
  # - ISFDB printings with the same publisher and the same cover share a
  #   card: the same scan (Orbit's 1979 and 1985 Birthgrave), or the same
  #   ISBN and cover artist (DAW's 1975 Birthgrave is in ISFDB twice, once
  #   undated, with two scans of George Barr's cover). The card's record is
  #   the printing with a cover and a date.
  # - An Open Library edition joins the ISFDB card that has its ISBN — if
  #   only one does: a reused ISBN on several covers (Orbit's Birthgrave
  #   0860079422, 1977 and 1979/85) can't say which, so it stays apart.
  #   Otherwise Open Library editions group by ISBN among themselves (it
  #   lists one Tor edition under "Tor" and "Tom Doherty Associates").
  # - Other-language editions are left out unless asked for (Open Library
  #   lists translations under the work); ebook and audio come last.
  class EditionCards
    Card = Struct.new(:editions, keyword_init: true) do
      def primary
        editions.select { |e| e.provider == "isfdb" }.min_by { |e| [ e.cover_url.present? ? 0 : 1, e.publish_date.present? ? 0 : 1 ] } ||
          editions.first
      end

      def cover_url = editions.filter_map(&:cover_url).first

      def publisher = primary.publisher.presence || editions.filter_map(&:publisher).first

      def years = editions.filter_map { |e| e.publish_date.to_s[/\A\d{4}/] }.uniq.sort

      def isbns = editions.filter_map(&:isbn).uniq

      def cover_artist = editions.filter_map(&:cover_artist).first

      def providers = editions.map(&:provider).uniq

      def physical? = editions.any? { |e| !e.binding.to_s.match?(ProviderEdition::NON_PHYSICAL) }

      def format_label = EditionCards.format_label(primary.binding)

      def sort_key = [ physical? ? 0 : 1, years.first || "9999", publisher.to_s ]
    end

    FORMAT_LABELS = { "pb" => "Mass-market paperback", "tp" => "Trade paperback", "hc" => "Hardback", "ebook" => "Ebook",
                      "digest" => "Digest" }.freeze
    ENGLISH = [ nil, "", "eng", "en", "english" ].freeze

    def self.format_label(binding)
      return if binding.blank?

      FORMAT_LABELS[binding.downcase] || binding.to_s.downcase.capitalize
    end

    # -> [cards, hidden_count]
    def self.build(editions, all_languages: false)
      shown, hidden = editions.partition { |e| all_languages || ENGLISH.include?(e.language.to_s.downcase) }
      isfdb, others = shown.partition { |e| e.provider == "isfdb" }

      cards = []
      isfdb.each do |e|
        home = cards.find { |c| c.editions.any? { |o| same_cover?(e, o) } }
        home ? home.editions << e : cards << Card.new(editions: [ e ])
      end
      others.group_by { |e| e.isbn || "#{e.provider}:#{e.id}" }.each_value do |eds|
        homes = eds.first.isbn ? cards.select { |c| c.isbns.include?(eds.first.isbn) } : []
        homes.one? ? homes.first.editions.concat(eds) : cards << Card.new(editions: eds)
      end
      [ cards.sort_by(&:sort_key), hidden.size ]
    end

    def self.same_cover?(a, b)
      return false unless publisher_core(a.publisher) == publisher_core(b.publisher)
      return true if a.cover_url.present? && a.cover_url == b.cover_url

      a.isbn.present? && a.isbn == b.isbn && a.cover_artist.present? && a.cover_artist == b.cover_artist
    end

    GENERIC_PUBLISHER_WORDS = %w[books book publishing publishers press paperbacks paperback ltd inc the co].freeze

    # "Panther / Granada" -> "panther", "Pan Books" -> "pan".
    def self.publisher_core(publisher)
      words = I18n.transliterate(publisher.to_s.split(" / ").first.to_s).downcase.gsub(/[^a-z0-9]+/, " ").split
      (words - GENERIC_PUBLISHER_WORDS).join(" ")
    end

    # A catalogued work's known editions (provider_editions) as provider
    # records — no network.
    def self.from_provider_editions(rows)
      rows.map do |r|
        Providers::Edition.new(provider: r.provider, id: r.provider_id, title: r.title, isbn13: r.isbn13, isbn10: r.isbn10,
                               publisher: r.publisher, binding: r.binding, publish_date: r.publish_date, language: r.language,
                               page_count: r.page_count, cover_url: r.cover_url, cover_artist: r.cover_artist,
                               pub_series_id: r.pub_series_id, pub_series_name: r.pub_series_name, pub_series_num: r.pub_series_num,
                               series_id: r.series_id, series_name: r.series_name, series_num: r.series_num)
      end
    end
  end
end

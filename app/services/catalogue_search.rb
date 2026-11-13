# The header search box: find a book in the catalogue by title, subtitle,
# author, series, or an ISBN / Goodreads / ISFDB id. Every typed word
# must start a word somewhere in the book's text — "found asim" finds
# Foundation by Asimov — with accents and punctuation folded (Cat’s
# Cradle, Le Guin, Lem's Solaris). In memory: the catalogue is a few
# thousand works, already loaded whole by the books list.
module CatalogueSearch
  def self.filter(works, query)
    words = fold(query).split
    return works if words.empty?

    if (isbn = Isbn.normalize(query)) || query.strip.match?(/\A\d+\z/)
      ids = [ isbn, isbn && Isbn.to_13(isbn), isbn && Isbn.to_10(isbn), query.strip ].compact
      by_id = works.select { |w| w.editions.any? { |e| e.edition_identifiers.any? { |i| ids.include?(i.value) } } }
      return by_id if by_id.any?
    end

    works.select do |work|
      text = haystack(work)
      words.all? { |word| text.include?(" #{word}") }
    end
  end

  def self.haystack(work)
    # Every title the book goes by: its own, the ones it had before a
    # rename (alternate titles), and ISFDB's other titles for it — the
    # title an edition was printed under ("The Judgement of Eve" for The
    # Judgment of Eve, 2026-11-13).
    " " + fold([ work.title, work.subtitle, *work.work_alternate_titles.map(&:title), *work.isfdb_variant_titles,
                 *work.authors.map(&:name), *work.series.map(&:name) ].compact.join(" ")) + " "
  end

  def self.fold(text) = I18n.transliterate(text.to_s.tr("’‘", "''")).downcase.delete("'").gsub(/[^a-z0-9]+/, " ").strip
end

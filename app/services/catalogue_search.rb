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
    " " + fold([ work.title, work.subtitle, *work.authors.map(&:name), *work.series.map(&:name) ].compact.join(" ")) + " "
  end

  def self.fold(text) = I18n.transliterate(text.to_s.tr("’‘", "''")).downcase.delete("'").gsub(/[^a-z0-9]+/, " ").strip
end

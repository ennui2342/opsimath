# Which of a provider's works is our book, by title and author — one rule
# for every provider (docs/CATALOG.md, "Anchored editions" → "Book-level
# links"). A provider only says how to search (Providers::*#search_works);
# what counts as a match lives here.
#
# A provider often holds several records under one title and author:
# translations that kept the title (ISFDB's German and Dutch "Lexicon"),
# adaptations ("Kindred: A Graphic Novel Adaptation"), one book credited
# two ways (Brian / Brian M. Stableford's "The Paradise Game"). So: records
# with no English printing are dropped, an exact full-title match is
# preferred, and identical English records are taken together. Anything
# still ambiguous ("The Past Through Tomorrow: Vol. 2" against "Vol. 1"
# and "Book One") takes nothing — never a guess.
module WorkMatcher
  ENGLISH = [ "eng", "en", "english" ].freeze

  # -> the matching works (several only when they're the same book), or []
  def self.match(works, title:, author: nil)
    surname = surname(author)
    candidates = Array(works).select do |w|
      key(short(w.title)) == key(short(title)) &&
        (surname.nil? || Array(w.authors).any? { |a| surname(a) == surname }) &&
        english?(w)
    end
    exact = candidates.select { |w| key(w.title) == key(title) }
    candidates = exact if exact.any?
    return candidates if candidates.size == 1 || (candidates.size > 1 && exact.size == candidates.size)

    []
  end

  # No language known counts as English: most records don't say.
  def self.english?(work)
    langs = Array(work.languages).map { |l| l.to_s.downcase }.reject(&:blank?)
    langs.empty? || langs.intersect?(ENGLISH)
  end

  def self.english_language?(language) = language.blank? || ENGLISH.include?(language.to_s.downcase)

  SUFFIXES = %w[jr sr ii iii iv].freeze

  # "Kurt Vonnegut, Jr." -> "vonnegut"; "Ursula K. Le Guin" -> "guin".
  def self.surname(name) = (fold(name).split - SUFFIXES).last

  # A title for comparison: folded, without a leading article ("The
  # Futurological Congress" is Lem's "Futurological Congress").
  def self.key(title) = fold(title).sub(/\A(the|a|an) /, "")

  def self.short(text) = text.to_s.split(/[:(]/).first.to_s

  def self.fold(text) = I18n.transliterate(text.to_s.tr("’‘", "''")).downcase.delete("'").gsub(/[^a-z0-9]+/, " ").strip
end

# How opsimath compares titles — one rule everywhere a title is matched:
# Add a book's search, the header search (CatalogueSearch), and the
# matcher behind the edition picker and the nightly lookups (WorkMatcher).
# Until 2026-11-15 each had its own, and each missed something different
# (Mark: "is the search shared between different systems that do title
# match?" — it wasn't).
#
# Folded: accents and case gone; "&" is "and" (Machines & Men is ISFDB's
# Machines and Men); apostrophes dropped, not spaced ("Year's"
# is "years", as typed); numbers as digits, whether written as words or
# Roman numerals ("Two", "II" are "2"; a lone "I" stays a word: I, Robot);
# and a volume word before a number dropped ("No. 2", "Vol. 2", "Book 2"
# are "2") — anthologies and series write them every way.
module TitleWords
  NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
                    sixteen seventeen eighteen nineteen twenty].freeze
  ROMAN = %w[ii iii iv v vi vii viii ix x xi xii xiii xiv xv xvi xvii xviii xix xx].each_with_index.to_h { |r, i| [ r, i + 2 ] }.freeze
  VOLUME_WORDS = %w[no number vol volume book].freeze

  def self.fold(text)
    words = I18n.transliterate(text.to_s.tr("’‘", "''")).downcase.gsub("&", " and ").delete("'").gsub(/[^a-z0-9]+/, " ").split
    words = words.map { |w| (n = number(w)) ? n.to_s : w }
    words.each_with_index.reject { |w, i| VOLUME_WORDS.include?(w) && words[i + 1]&.match?(/\A\d+\z/) }.map(&:first).join(" ")
  end

  # A word as a number: digits, a number word, or a Roman numeral II–XX.
  def self.number(word)
    return word.to_i if word.match?(/\A\d+\z/)

    NUMBER_WORDS.index(word) || (word.size > 1 ? ROMAN[word] : nil)
  end
end

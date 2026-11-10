# A book's title against ISFDB's main title (docs/CATALOG.md, "Titles from
# ISFDB"): the book's title is ISFDB's main title — generally the title of
# first publication — as for a book added from ISFDB (Mark, 2026-11-10); an
# edition printed under another title says so on its card ("as Voyage to
# Venus"), and a replaced title is kept as an alternate title, so search
# still finds it. A difference is one of:
#   :brackets  — Goodreads' series / imprint note on the end, otherwise the
#                same ("World's End (Snow Queen Vol. 2)")
#   :cosmetic  — the same words but for capitals, punctuation, "&"/"and" or a
#                leading article ("Shadrach In The Furnace")
#   :variant   — one of the main title's variant titles: the same book known
#                by another title (Extro / The Computer Connection)
#   :reworded  — shares words with it: a subtitle added or dropped, a
#                rewording (The Dispossessed: An Ambiguous Utopia)
#   :suspect   — shares nothing with the main title or any variant: likely a
#                book linked to the wrong ISFDB record (Kesrith → The Faded
#                Sun Trilogy) — listed in Settings → Titles to review, to fix
#                the link, never retitled here.
# AUTOMATIC kinds are applied nightly. A title Mark set himself
# (field_sources "manual" — the cog, or "Keep mine") is never touched.
class TitleCleanup
  Fix = Struct.new(:work, :from, :to, :kind, keyword_init: true)

  AUTOMATIC = %i[brackets cosmetic].freeze
  BRACKETED = /\s*\([^()]+\)\s*\z/
  STOP = %w[the a an of and in on to for with by at from or s].freeze

  def self.plan(works = Work.all) = new.plan(works)

  def self.apply(works = Work.all, kinds: AUTOMATIC) = new.apply(works, kinds:)

  # -> every difference, each with its kind
  def plan(works)
    works.includes(:provider_editions).find_each.filter_map { |w| fix_for(w) }
  end

  # -> number of books retitled
  def apply(works, kinds:)
    fixes = plan(works).select { |f| kinds.include?(f.kind) }
    fixes.each { |f| self.class.retitle(f.work, f.to, source: "isfdb") }
    fixes.size
  end

  # Set a book's title, with where it came from, and say so. The title it
  # replaces stays findable, as an alternate title.
  def self.retitle(work, title, source:)
    from = work.title
    work.update!(title:, field_sources: work.field_sources.merge("title" => source))
    return if from == title

    unless work.work_alternate_titles.exists?(title: from)
      work.work_alternate_titles.create!(title: from, note: "its title before #{source == 'manual' ? 'Mark set it' : "ISFDB's"}")
    end
    CatalogueEvent.record(kind: "retitled", origin: (source == "manual" ? nil : "title_cleanup"), work:,
                          summary: "Retitled “#{from}” to #{source == 'manual' ? '' : "ISFDB's "}“#{title}”")
  end

  # ISFDB's main title, once fetched (Isfdb::MainTitles).
  def self.isfdb_title(work) = work.isfdb_main_title.presence

  private

  def fix_for(work)
    return if work.field_sources["title"] == "manual"

    main = self.class.isfdb_title(work) or return
    return if work.title == main || !main.match?(/[[:alpha:]]/) # ISFDB's title "/" (Slant)

    Fix.new(work:, from: work.title, to: main, kind: kind_of(work, main))
  end

  def kind_of(work, main)
    title = work.title
    plain = title.sub(BRACKETED, "")
    return :brackets if plain != title && (fold(plain) == fold(main) || longer_form?(fold(plain), fold(main)))
    return :cosmetic if fold(title).delete(" ") == fold(main).delete(" ") # "Brainrose" / "Brain Rose"
    # Different volume numbers: linked to another volume ("Book Two" →
    # "Volume One"), whatever else matches.
    return :suspect if numbers_differ?(plain, main)
    return :variant if work.isfdb_variant_titles.any? { |v| [ fold(title), fold(plain) ].include?(fold(v)) }
    return :reworded if (words(plain) & words(main)).any?

    :suspect
  end

  # "All the Traps of Earth (collection of stories)" for "…and Other
  # Stories" — but not one word standing for a different title.
  def longer_form?(short, long) = short.split.size >= 3 && long.start_with?("#{short} ")

  def words(text) = fold(text).split - STOP

  NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve].each_with_index.to_h
                                                                                       .merge("first" => 1, "second" => 2, "third" => 3, "fourth" => 4, "fifth" => 5).freeze

  # The titles' numbers ("2", "Two", "Second") aren't the same — including
  # Mark's title numbering a volume ISFDB's doesn't: a UK split
  # ("Dangerous Visions 1", "A Storm of Swords 2") linked to the whole.
  def numbers_differ?(mine, isfdb)
    na, nb = numbers(mine), numbers(isfdb)
    na.any? && na != nb
  end

  def numbers(text) = fold(text).split.filter_map { |w| w.match?(/\A\d+\z/) ? w.to_i : NUMBER_WORDS[w] }.to_set

  def fold(text)
    I18n.transliterate(text.to_s).downcase.gsub("&", " and ").gsub(/(\d)'s\b/, "\\1s")
        .gsub(/[^a-z0-9]+/, " ").strip.sub(/\A(the|a|an) /, "")
  end
end

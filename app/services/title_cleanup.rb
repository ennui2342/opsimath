# A book's title against ISFDB's, for books linked to ISFDB (docs/
# CATALOG.md, "Titles from ISFDB"). ISFDB's title is the one most of the
# book's ISFDB printings carry. A difference is one of:
#   :brackets  — Goodreads' series / imprint note on the end, otherwise the
#                same ("World's End (Snow Queen Vol. 2)")
#   :cosmetic  — the same words but for capitals, punctuation, "&"/"and" or
#                a leading article ("Shadrach In The Furnace")
#   :different — anything else: a UK/US title, a marketing subtitle, or a
#                book linked to the wrong ISFDB record (Kesrith → The Faded
#                Sun Trilogy) — Mark's to review, never changed here.
# The first two are applied nightly (Mark, 2026-11-10); a title Mark set
# himself (field_sources "manual" — the cog, or "Keep mine" on review) is
# never touched or listed.
class TitleCleanup
  Fix = Struct.new(:work, :from, :to, :kind, keyword_init: true)

  AUTOMATIC = %i[brackets cosmetic].freeze
  BRACKETED = /\s*\([^()]+\)\s*\z/

  def self.plan(works = Work.all) = new.plan(works)

  def self.apply(works = Work.all) = new.apply(works)

  # -> every difference, each with its kind
  def plan(works)
    works.includes(:provider_editions).find_each.filter_map { |w| fix_for(w) }
  end

  # -> number of books retitled (the automatic kinds)
  def apply(works)
    fixes = plan(works).select { |f| AUTOMATIC.include?(f.kind) }
    fixes.each { |f| self.class.retitle(f.work, f.to, source: "isfdb") }
    fixes.size
  end

  # Set a book's title, with where it came from, and say so.
  def self.retitle(work, title, source:)
    from = work.title
    work.update!(title:, field_sources: work.field_sources.merge("title" => source))
    return if from == title

    CatalogueEvent.record(kind: "retitled", origin: (source == "manual" ? nil : "title_cleanup"), work:,
                          summary: "Retitled “#{from}” to #{source == 'manual' ? '' : "ISFDB's "}“#{title}”")
  end

  def self.isfdb_title(work)
    work.provider_editions.select { |p| p.provider == "isfdb" }.filter_map(&:title).tally.max_by(&:last)&.first
  end

  private

  def fix_for(work)
    return if work.field_sources["title"] == "manual"

    isfdb = self.class.isfdb_title(work) or return
    return if work.title == isfdb

    Fix.new(work:, from: work.title, to: isfdb, kind: kind_of(work.title, isfdb))
  end

  def kind_of(title, isfdb)
    plain = title.sub(BRACKETED, "")
    return :brackets if plain != title && (fold(plain) == fold(isfdb) || longer_form?(fold(plain), fold(isfdb)))
    return :cosmetic if fold(title) == fold(isfdb)

    :different
  end

  # "All the Traps of Earth (collection of stories)" for "…and Other
  # Stories" — but not one word standing for a different title.
  def longer_form?(short, long) = short.split.size >= 3 && long.start_with?("#{short} ")

  def fold(text)
    I18n.transliterate(text.to_s).downcase.gsub("&", " and ").gsub(/(\d)'s\b/, "\\1s")
        .gsub(/[^a-z0-9]+/, " ").strip.sub(/\A(the|a|an) /, "")
  end
end

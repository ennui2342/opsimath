# Titles the Goodreads import left with a bracketed series, imprint or
# edition note on the end — "World's End (Snow Queen Vol. 2)", "Mindbridge
# (Orbit Books)", "Fury (U.K.)" — set to ISFDB's title for the book, when
# that's the same title with the brackets gone (casing and "&"/"and" aside,
# or a longer/shorter form of it of three words or more: "All the Traps of
# Earth and Other Stories"). A title Mark set himself is left; one without an ISFDB title
# is listed, not touched — brackets are sometimes the real title
# ("Interzone #282 (July-August 2019)").
class TitleCleanup
  Fix = Struct.new(:work, :from, :to, keyword_init: true)

  BRACKETED = /\s*\([^()]+\)\s*\z/

  def self.plan = new.plan

  def self.apply = new.apply

  # -> [fixes, left alone (without an ISFDB title, or not the same title)]
  def plan
    candidates = Work.includes(:provider_editions).select { |w| w.title.to_s.match?(BRACKETED) }
    fixes = candidates.filter_map { |w| fix_for(w) }
    [ fixes, candidates - fixes.map(&:work) ]
  end

  # -> number of books retitled
  def apply
    fixes, = plan
    fixes.each do |f|
      f.work.update!(title: f.to, field_sources: f.work.field_sources.merge("title" => "isfdb"))
      CatalogueEvent.record(kind: "retitled", origin: "title_cleanup", work: f.work,
                            summary: "Retitled “#{f.from}” to ISFDB's “#{f.to}”")
    end
    fixes.size
  end

  private

  def fix_for(work)
    return if work.field_sources["title"] == "manual"

    isfdb = isfdb_title(work) or return
    return if work.title.casecmp?(isfdb)

    a, b = fold(work.title.sub(BRACKETED, "")), fold(isfdb)
    Fix.new(work:, from: work.title, to: isfdb) if a == b || longer_form?(a, b) || longer_form?(b, a)
  end

  # "All the Traps of Earth" for "…and Other Stories" — but not one word
  # standing for a different title ("Clarion", "The Clarion Anthology").
  def longer_form?(short, long) = short.split.size >= 3 && long.start_with?("#{short} ")

  # The title most of the book's ISFDB printings carry.
  def isfdb_title(work)
    work.provider_editions.select { |p| p.provider == "isfdb" }.filter_map(&:title).tally.max_by(&:last)&.first
  end

  def fold(text)
    I18n.transliterate(text.to_s).downcase.gsub("&", " and ").gsub(/(\d)'s\b/, "\\1s")
        .gsub(/[^a-z0-9]+/, " ").strip.sub(/\A(the|a|an) /, "")
  end
end

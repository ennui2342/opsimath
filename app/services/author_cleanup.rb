# Book authors checked against ISFDB's (2026-11-13). The Goodreads import
# made everyone Goodreads listed an author — translators, introducers,
# every contributor to an anthology — and some names arrived mangled
# ("Larry; Barnes Niven", slugs like "greg-bear", or the same person twice
# as "C.J. Cherryh" and "c-j-cherryh").
#
# Book-level credits come from the book's ISFDB title (isfdb-adapter
# /titles/:id main.authors — the title that is this book, by
# Isfdb::MainTitles.ordered), not a printing's. For each linked book:
#
#   - one of ours is ISFDB's author if the names agree once case, accents,
#     punctuation, order and Jr. are set aside, or by surname and first
#     initial (Brian M. Stableford / Brian Stableford), or by ISFDB id —
#     or if it's a name the title's variants are credited under (a
#     pseudonym: John Beynon for John Wyndham);
#   - anyone else stays on the book as a contributor, not an author;
#   - a mangled name (a slug, "A; B", "A & B", all lower or upper case, a
#     bare surname) is replaced by ISFDB's credits;
#   - an ISFDB author the book lacks is added (Mutant: C. L. Moore).
#
# A book whose ISFDB link is suspect (TitleCleanup) is left alone. People
# who are the same — one ISFDB id, or the same name — are merged into one
# first. `plan` is a dry run.
class AuthorCleanup
  Change = Struct.new(:work, :demote, :remove, :add, :link, keyword_init: true) # demote/remove: Contributors; add: [name, isfdb id]; link: {Contributor => isfdb id}
  Merge = Struct.new(:keep, :drop, keyword_init: true)

  POOL_SIZE = 4

  def self.plan(...) = new(...).plan

  def self.apply(...) = new(...).apply

  def initialize(works: nil, client: Isfdb::Client.new)
    @works = works
    @client = client
  end

  # -> [merges, changes]
  def plan
    [ merges, changes ]
  end

  # -> [people merged, books changed]
  def apply
    merged = 0
    Contributor.transaction { merges.each { |m| merge!(m) && merged += 1 } }
    @changes = nil
    done = changes.count { |c| Contributor.transaction { change!(c) } }
    [ merged, done ]
  end

  # --- names --------------------------------------------------------------

  SUFFIX = /\b(jr|sr|ii|iii)\b/

  def self.tokens(name)
    I18n.transliterate(CGI.unescapeHTML(name.to_s).sub(/\s*\([IVX]+\)\z/, "")).downcase.gsub(/[^a-z ]/, " ").gsub(SUFFIX, " ").split
  end

  def self.same?(ours, theirs)
    a = tokens(ours)
    b = tokens(theirs)
    return false if a.empty? || b.empty? || a.one? || b.one?
    return true if a.sort == b.sort || a.join == b.join

    a.last == b.last && a.first[0] == b.first[0]
  end

  def self.mangled?(name)
    name.match?(/\A[a-z0-9]+(-[a-z0-9]+)+\z/) || name.match?(/[;&]/) || name == name.downcase ||
      (name == name.upcase && name.match?(/[A-Z]{2}/)) || !name.strip.include?(" ")
  end

  # An author's name in Latin script: ISFDB's canonical name for a
  # Russian author is Cyrillic (Борис Стругацкий); the book's English
  # variants are credited under "Boris Strugatsky".
  def self.latin_name(author, aliases)
    names = [ author["name"], *aliases.select { |al| al["of"].include?(author["id"]) }.map { |al| al["name"] } ].map { |n| clean(n) }
    names.find { |n| n.match?(/\A[\p{Latin}\p{Common}\p{Inherited}]+\z/) } || names.first
  end

  # ISFDB's form of a name: entities decoded, a disambiguator dropped
  # ("Ben Smith (I)").
  def self.clean(name) = CGI.unescapeHTML(name.to_s).sub(/\s*\([IVX]+\)\z/, "").strip

  private

  # --- merging the same person -------------------------------------------

  def merges
    @merges ||= begin
      people = Contributor.all.to_a
      groups = people.group_by { |c| c.external_ids["isfdb"].presence || "name:#{self.class.tokens(c.name).join(' ')}" }.values
      # Same name, no ISFDB id, joins a group with one.
      by_name = people.group_by { |c| self.class.tokens(c.name).join(" ") }
      seen = Set.new
      (groups + by_name.values).filter_map do |group|
        ids = group.filter_map { |c| c.external_ids["isfdb"].presence }.uniq
        next if group.size < 2 || ids.size > 1 # two people, one name (Ben Smith)

        group = group.reject { |c| seen.include?(c.id) }
        next if group.size < 2

        seen.merge(group.map(&:id))
        keep = group.min_by { |c| [ self.class.mangled?(c.name) ? 1 : 0, -c.work_contributors.size, c.id ] }
        Merge.new(keep:, drop: group - [ keep ])
      end
    end
  end

  def merge!(m)
    m.drop.each do |dup|
      dup.work_contributors.each do |wc|
        if WorkContributor.exists?(work_id: wc.work_id, contributor_id: m.keep.id, role: wc.role) then wc.destroy!
        else wc.update!(contributor: m.keep)
        end
      end
      dup.edition_contributors.each do |ec|
        if EditionContributor.exists?(edition_id: ec.edition_id, contributor_id: m.keep.id, role: ec.role) then ec.destroy!
        else ec.update!(contributor: m.keep)
        end
      end
      EnrichmentRecord.where(entity: dup).update_all(entity_id: m.keep.id)
      m.keep.external_ids = dup.external_ids.merge(m.keep.external_ids)
      m.keep.died_date ||= dup.died_date
      m.keep.bio ||= dup.bio
      dup.reload.destroy!
    end
    m.keep.save!
  end

  # --- each book against its ISFDB title ---------------------------------

  def changes
    @changes ||= begin
      works = @works || Work.where(id: WorkIdentifier.where(id_type: "isfdb_title").select(:work_id))
      titles = fetch(works)
      Work.where(id: titles.keys).includes(work_contributors: :contributor).filter_map do |work|
        next if TitleCleanup.suspect?(work)

        main = Isfdb::MainTitles.ordered(titles[work.id], work.title).first["main"]
        change_for(work, Array(main["authors"]), Array(main["author_aliases"]))
      end
    end
  end

  def fetch(works)
    ids = WorkIdentifier.where(id_type: "isfdb_title", work_id: works.select(:id)).order(:id).pluck(:work_id, :value).group_by(&:first)
    found = Concurrent::Hash.new
    pool = Concurrent::FixedThreadPool.new(POOL_SIZE)
    ids.each do |work_id, rows|
      pool.post do
        found[work_id] = rows.map(&:last).filter_map { |id| @client.title(id) }
      rescue StandardError => e
        Rails.logger.warn("Author cleanup: work ##{work_id} — #{e.class}: #{e.message}")
      end
    end
    pool.shutdown
    pool.wait_for_termination(30.minutes)
    found.select { |_, records| records.any? { |r| r.dig("main", "authors") } }
  end

  def change_for(work, authors, aliases)
    return if authors.empty?

    ours = work.work_contributors.select { |wc| wc.role == "author" }.map(&:contributor)
    matched = {} # isfdb author id => Contributor
    link = {}
    demote = []
    remove = []
    ours.each do |c|
      a = authors.find { |x| c.external_ids["isfdb"] == x["id"] } || authors.find { |x| self.class.same?(c.name, self.class.clean(x["name"])) }
      if a
        matched[a["id"]] = c
        link[c] = a["id"] if c.external_ids["isfdb"].blank?
      elsif (al = aliases.find { |x| c.external_ids["isfdb"] == x["id"] || self.class.same?(c.name, self.class.clean(x["name"])) })
        al["of"].each { |id| matched[id] ||= c } # a pseudonym stands for its author(s)
      elsif self.class.mangled?(c.name)
        remove << c
      else
        demote << c
      end
    end
    add = authors.reject { |a| matched.key?(a["id"]) }.map { |a| [ self.class.latin_name(a, aliases), a["id"] ] }
    return if demote.empty? && remove.empty? && add.empty? && link.empty?

    Change.new(work:, demote:, remove:, add:, link:)
  end

  def change!(c)
    work = c.work
    c.link.each { |person, id| person.update!(external_ids: person.external_ids.merge("isfdb" => id)) unless Contributor.where("external_ids->>'isfdb' = ?", id).where.not(id: person.id).exists? }
    rows = work.work_contributors.where(role: "author")
    c.remove.each { |person| rows.where(contributor: person).destroy_all }
    c.demote.each do |person|
      wc = rows.find_by(contributor: person) or next
      if work.work_contributors.exists?(contributor: person, role: "contributor") then wc.destroy!
      else wc.update!(role: "contributor")
      end
    end
    order = work.work_contributors.where(role: "author").maximum(:display_order).to_i
    c.add.each do |name, id|
      person = Contributor.find_by("external_ids->>'isfdb' = ?", id) ||
               Contributor.all.find { |p| p.external_ids["isfdb"].blank? && self.class.same?(p.name, name) } ||
               Contributor.create!(name:, external_ids: { "isfdb" => id }, field_sources: { "name" => "isfdb" })
      next if work.work_contributors.exists?(contributor: person, role: "author")

      work.work_contributors.where(contributor: person).destroy_all # was a contributor: now the author
      work.work_contributors.create!(contributor: person, role: "author", display_order: order += 1)
    end
    CatalogueEvent.record(kind: "authors", work:, summary: "#{work.title}: authors checked against ISFDB")
    true
  end
end

# Ties the catalogue's authors to ISFDB's through the books they wrote
# (docs/CATALOG.md, "Authors linked through their books"): a book linked
# to an ISFDB title has printings crediting ISFDB authors by id
# (KnownEditionsRefresh keeps them). Name search — the only way before
# 2026-11-08, and only for wanted books' authors — stays the fallback
# (Isfdb::ContributorLifeRefresh).
#
# For each author, over their books' own ISFDB printings (not an
# omnibus's):
#   - a credit with the same name (case and punctuation folded) is theirs;
#   - else, where the book has one author and the printing credits one, a
#     different name (a pseudonym, "J.G." for "J. G.") is theirs if at
#     least two books agree.
# One id that way links an unlinked author. One already linked by name to
# a different id is reported (`plan`), not changed.
class AuthorLinks
  Link = Struct.new(:contributor, :isfdb_id, :books, :how, :current, keyword_init: true) # how: :name | :sole_author

  def self.plan = new.plan

  def self.run = new.run

  # -> [links to make, disagreements with an existing link]
  def plan
    found = Contributor.where(id: WorkContributor.where(role: "author").select(:contributor_id))
                       .includes(work_contributors: { work: [ :provider_editions, :work_contributors ] }).filter_map { |c| link_for(c) }
    found.partition { |l| l.current.nil? }.then { |new_links, linked| [ new_links, linked.reject { |l| l.current == l.isfdb_id.to_s } ] }
  end

  # -> number of authors linked
  def run
    links, = plan
    links.each do |l|
      l.contributor.update_columns(external_ids: l.contributor.external_ids.merge("isfdb" => l.isfdb_id.to_s),
                                   field_sources: l.contributor.field_sources.merge("isfdb_id" => "books"),
                                   life_checked_at: nil) # its dates are read by id on the next check
    end
    links.size
  end

  private

  def link_for(contributor)
    by_name = Hash.new { |h, k| h[k] = [] }
    sole = Hash.new { |h, k| h[k] = [] }
    contributor.work_contributors.select { |wc| wc.role == "author" }.map(&:work).uniq.each do |work|
      own_printings(work).each do |p|
        credits = p.author_names.zip(p.author_ids).select { |_, id| id }
        if (match = credits.find { |name, _| Authority.normalize(name) == Authority.normalize(contributor.name) })
          by_name[match.last] << work
        elsif credits.one? && work.work_contributors.count { |wc| wc.role == "author" } == 1
          sole[credits.first.last] << work
        end
      end
    end
    current = contributor.external_ids["isfdb"].presence

    if by_name.keys.one?
      id, works = by_name.first
      Link.new(contributor:, isfdb_id: id, books: works.uniq.size, how: :name, current:)
    elsif by_name.empty? && sole.keys.one? && sole.values.first.uniq.size >= 2
      id, works = sole.first
      Link.new(contributor:, isfdb_id: id, books: works.uniq.size, how: :sole_author, current:)
    end
  end

  def own_printings(work)
    key = WorkMatcher.key(WorkMatcher.short(work.title))
    work.provider_editions.select { |p| p.provider == "isfdb" && p.author_ids.any? && WorkMatcher.key(WorkMatcher.short(p.title.to_s)) == key }
  end
end

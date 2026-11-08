# The Goodreads import recorded some cover artists as co-authors (Slan:
# A.E. van Vogt, Chris Foss) — Goodreads lists illustrators alongside
# authors. Found 2026-11-08 once author pages made it visible. A co-author
# credit (not the first-listed author) is a misfiled cover credit when
#
#   - ISFDB names them as a cover artist of one of *this* book's printings, or
#   - they're a known cover artist anywhere in the catalogue and never the
#     first-listed author of any book (Keith Roberts painted covers too, and
#     wrote; he's left alone)
#
# The author credit goes; if the book's edition has no cover artist on
# file, the name goes there instead (the credit isn't lost); an artist
# left with no books goes. `plan` is a dry run.
class MisfiledArtistCleanup
  Fix = Struct.new(:work_contributor, :reason, :fill_editions, keyword_init: true)

  def self.plan = new.plan

  def self.apply = new.apply

  def plan
    credits = WorkContributor.where(role: "author").where("display_order > 0")
                             .includes(:contributor, work: :editions).to_a
    credits.filter_map do |wc|
      name = key(wc.contributor.name)
      reason =
        if artists_by_work[wc.work_id].include?(name) then "ISFDB credits them with this book's cover"
        elsif known_artists.include?(name) && !lead_authors.include?(name) then "a cover artist, never a lead author"
        end
      next unless reason

      Fix.new(work_contributor: wc, reason:, fill_editions: wc.work.editions.select { |e| e.cover_artist.blank? })
    end
  end

  # -> number of credits moved
  def apply
    fixes = plan
    WorkContributor.transaction do
      fixes.each do |fix|
        name = fix.work_contributor.contributor.name
        fix.fill_editions.each do |e|
          e.update!(cover_artist: name, field_sources: e.field_sources.merge("cover_artist" => "goodreads"))
        end
        fix.work_contributor.destroy!
      end
      orphans = Contributor.where(id: fixes.map { |f| f.work_contributor.contributor_id })
                           .where.missing(:work_contributors).where.missing(:edition_contributors)
      orphans.destroy_all
    end
    if fixes.any?
      CatalogueEvent.record(kind: "cleanup", origin: "web",
                            summary: "Moved #{fixes.size} cover-artist credits off books' authors (#{fixes.map { |f| f.work_contributor.contributor.name }.tally.sort_by { |_, n| -n }.first(5).map(&:first).join(', ')}…)")
    end
    fixes.size
  end

  private

  def key(name) = name.to_s.downcase.strip

  def split(credit) = credit.to_s.split(", ").map { |a| key(a) }

  def artists_by_work
    @artists_by_work ||= Hash.new { |h, k| h[k] = Set.new }.tap do |by|
      ProviderEdition.where(provider: "isfdb").where.not(cover_artist: [ nil, "" ]).pluck(:work_id, :cover_artist)
                     .each { |w, a| by[w].merge(split(a)) }
      Edition.joins(:edition_contents).where.not(cover_artist: [ nil, "" ]).pluck("edition_contents.work_id", :cover_artist)
             .each { |w, a| by[w].merge(split(a)) }
    end
  end

  def known_artists = @known_artists ||= artists_by_work.values.reduce(Set.new, :|)

  def lead_authors
    @lead_authors ||= WorkContributor.where(role: "author").where("display_order = 0 OR display_order IS NULL")
                                     .includes(:contributor).map { |wc| key(wc.contributor.name) }.to_set
  end
end

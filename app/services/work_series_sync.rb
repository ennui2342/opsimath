# Files books in their story series from ISFDB (docs/CATALOG.md, "Series
# from ISFDB"): a book's ISFDB printings name its title's series and its
# number there (KnownEditionsRefresh stores them). Until 2026-11-08 series
# came only from the Goodreads import, and Add a book set none — The Snow
# Queen sat outside The Snow Queen Cycle while its sequels were in it.
#
# Adds what's missing, never changes what's there: a book already in the
# series keeps its position (only an empty one is filled); a series of its
# own is never removed. The series is the one already tied to that ISFDB
# series, else one with the same name (a Goodreads-made one, which then
# gets tied to it), else one whose name is contained in ISFDB's or the
# other way round ("Confluence" / "The Book of Confluence") *and* whose
# books are all in that ISFDB series, else a new one. Never matched by the
# series a book's siblings are in alone: ISFDB files books in sub-series
# (Rincewind, within Discworld), and its numbers there aren't the parent's.
class WorkSeriesSync
  Change = Struct.new(:work, :series_name, :position, :action, keyword_init: true) # action: :add | :position

  def self.run(works = Work.all) = new.run(works)

  # Dry run: the changes `run` would make.
  def self.plan(works = Work.all) = new.plan(works)

  # -> number of books filed (or positions filled)
  def run(works)
    works.includes(:work_series, :provider_editions).find_each.count { |work| sync(work) }
  end

  def plan(works)
    works.includes(:work_series, :provider_editions).find_each.filter_map { |work| change_for(work) }
  end

  private

  def change_for(work)
    printing = series_printing(work) or return
    series = existing_series(printing)
    return if series.nil? && printing.series_name.blank?

    membership = series && work.work_series.find { |ws| ws.series_id == series.id }
    return Change.new(work:, series_name: series&.name || printing.series_name, position: printing.series_num, action: :add) unless membership
    return if membership.position || printing.series_num.nil?

    Change.new(work:, series_name: series.name, position: printing.series_num, action: :position)
  end

  def sync(work)
    change = change_for(work) or return false
    printing = series_printing(work)
    series = existing_series(printing, adopt: true) || Series.create!(name: printing.series_name, isfdb_series_id: printing.series_id)

    if change.action == :position
      work.work_series.find { |ws| ws.series_id == series.id }.update!(position: printing.series_num)
    else
      WorkSeries.create!(work:, series:, position: printing.series_num)
    end
    CatalogueEvent.record(kind: "series", origin: "work_series_sync", work:,
                          summary: "#{CatalogueEvent.title(work)}: in #{series.name}#{" ##{format('%g', printing.series_num)}" if printing.series_num} (from ISFDB)")
    true
  end

  # The series and number most of the book's own printings give.
  def series_printing(work)
    own_printings(work).select(&:series_id).group_by { |p| [ p.series_id, p.series_num ] }.max_by { |_, ps| ps.size }&.last&.first
  end

  # The book's own ISFDB printings — not an omnibus's that contains it,
  # whose title is in another series (or none).
  def own_printings(work)
    key = WorkMatcher.key(WorkMatcher.short(work.title))
    work.provider_editions.select { |p| p.provider == "isfdb" && WorkMatcher.key(WorkMatcher.short(p.title.to_s)) == key }
  end

  # The series tied to this ISFDB series, else one of the same name —
  # tied to it when `adopt:`.
  def existing_series(printing, adopt: false)
    Series.find_by(isfdb_series_id: printing.series_id) ||
      (named(printing.series_name) || near_named(printing))&.tap { it.update!(isfdb_series_id: printing.series_id) if adopt }
  end

  # A series whose name is within ISFDB's or holds it, word for word
  # ("Confluence" / "The Book of Confluence"), every book of which is in
  # that ISFDB series by its own printings — the same series under a
  # shorter or longer name, not a parent or a sub-series.
  def near_named(printing)
    name = fold(printing.series_name)
    return if name.blank?

    @unlinked_series ||= Series.where(isfdb_series_id: nil).includes(work_series: { work: :provider_editions }).to_a
    @unlinked_series.find do |s|
      next false if s.isfdb_series_id # tied earlier in this run
      other = fold(s.name)
      next false if other.blank? || other == name
      next false unless " #{name} ".include?(" #{other} ") || " #{other} ".include?(" #{name} ")

      works = s.work_series.map(&:work)
      works.any? && works.all? { |w| series_printing(w)&.series_id == printing.series_id }
    end
  end

  def fold(text) = I18n.transliterate(text.to_s).downcase.sub(/\Athe /, "").gsub(/[^a-z0-9]+/, " ").strip

  def named(name)
    return if name.blank?

    Series.where(isfdb_series_id: nil).where("name ILIKE ?", "%#{Series.sanitize_sql_like(name.sub(/\AThe /i, ''))}%")
          .find { |s| fold(s.name) == fold(name) }
  end
end

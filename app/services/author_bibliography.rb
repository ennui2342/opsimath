# An author as Mark sees them on their page: every book-length title of
# theirs ISFDB lists — English, in its own right (not a retitling or a
# translation) — beside the catalogue's books by them, grouped by kind,
# each with where it stands for him. The bibliography is kept on the
# Contributor, fetched in the background (AuthorBibliographyJob) when
# missing or a week old; until then the page shows the catalogue's books.
class AuthorBibliography
  Entry = Struct.new(:title_id, :title, :type, :year, :series, :series_num, :work, :status, keyword_init: true)
  # status: :owned | :wanted | :catalogued | :missing — as SeriesVolumes

  KINDS = { "NOVEL" => "Novels", "COLLECTION" => "Collections", "ANTHOLOGY" => "Anthologies", "NONFICTION" => "Non-fiction",
            "OMNIBUS" => "Omnibuses", "CHAPBOOK" => "Chapbooks" }.freeze
  STALE_AFTER = 7.days

  attr_reader :author, :entries

  def self.for(author) = new(author).tap(&:load)

  def initialize(author)
    @author = author
  end

  def fetched? = !@author.isfdb_works_fetched_at.nil?

  def stale? = !fetched? || @author.isfdb_works_fetched_at < STALE_AFTER.ago

  def load
    catalogue = @author.work_contributors.select { |wc| wc.role == "author" }.map(&:work).uniq
    from_isfdb = Array(@author.isfdb_works).filter_map { |w| from_isfdb(w) }.uniq(&:title_id)
    known = from_isfdb.filter_map(&:work).to_set
    rest = catalogue.reject { |w| known.include?(w) }.map do |w|
      Entry.new(title: w.title, type: (w.literary_form.to_s.upcase if KINDS.key?(w.literary_form.to_s.upcase)) || "NOVEL",
                year: w.original_publication_year, work: w)
    end
    @entries = (from_isfdb + rest).each { |e| e.status = status_of(e) }
                                  .sort_by { |e| [ e.year || 9999, e.title.to_s.downcase ] }
    self
  end

  # The page: Mark's own books first, by date; then the rest by kind.
  def owned = entries.select { |e| e.status == :owned }

  def by_kind = entries.reject { |e| e.status == :owned }.group_by(&:type).sort_by { |type, _| KINDS.keys.index(type) || 99 }

  def missing = entries.select { |e| %i[missing catalogued].include?(e.status) }

  private

  def from_isfdb(w)
    return if w["variant_of"].present? || !KINDS.key?(w["type"])
    return if w["language"].present? && !AddBook::EditionCards::ENGLISH.include?(w["language"].downcase)

    title_id = w["_isfdb_title_id"] or return
    Entry.new(title_id: title_id.to_i, title: w["title"], type: w["type"], year: w["publish_year"],
              series: w["series"].presence, series_num: w["_isfdb_series_num"], work: works_by_title_id[title_id.to_s])
  end

  def works_by_title_id
    @works_by_title_id ||= WorkIdentifier.where(id_type: "isfdb_title", value: Array(@author.isfdb_works).filter_map { |w| w["_isfdb_title_id"]&.to_s })
                                         .includes(work: WorksController::LIST_INCLUDES).to_h { |i| [ i.value, i.work ] }
  end

  def status_of(entry)
    return :missing unless entry.work

    statuses = entry.work.statuses
    return :owned if statuses.include?(:owned)
    return :wanted if statuses.include?(:wanted)

    :catalogued
  end
end

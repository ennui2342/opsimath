# A story series as Mark sees it on its page: every book in it, in series
# order — those in the catalogue (WorkSeries) and, when the series is tied
# to ISFDB, every book-length title ISFDB files there — each with where it
# stands for him. ISFDB's list from isfdb-adapter (cached a day); an
# omnibus in another language filed in the series (Le cycle de Tiamat)
# is left out.
class SeriesVolumes
  Entry = Struct.new(:title_id, :position, :title, :authors, :year, :cover_url, :work, :status, keyword_init: true)
  # status: :owned | :wanted | :catalogued (in the catalogue, neither) | :missing (not in the catalogue)

  attr_reader :series, :entries, :isfdb_id, :complete

  def self.for(series) = new(series).tap(&:load)

  def initialize(series)
    @series = series
  end

  def load
    @isfdb_id = @series.isfdb_series_id || inferred_isfdb_id
    volumes = @isfdb_id ? fetch : nil
    @complete = !volumes.nil?
    members = @series.work_series.includes(work: WorksController::LIST_INCLUDES).to_a
    from_isfdb = Array(volumes).filter_map { |v| from_volume(v) }
    known = from_isfdb.filter_map(&:work).to_set
    from_catalogue = members.reject { |ws| known.include?(ws.work) }.map do |ws|
      Entry.new(position: ws.position, title: ws.work.title, authors: ws.work.authors.map(&:name), work: ws.work,
                title_id: ws.work.work_identifiers.find { |i| i.id_type == "isfdb_title" }&.value&.to_i)
    end
    positions = members.to_h { |ws| [ ws.work_id, ws.position ] }
    @entries = (from_isfdb + from_catalogue).each do |e|
      e.position = positions[e.work.id] if e.work && positions[e.work.id] # Mark's numbering where he has one
      e.status = status_of(e)
    end.sort_by { |e| [ e.position || Float::INFINITY, e.year || 9999, e.title.to_s.downcase ] }
    self
  end

  def missing = entries.select { |e| %i[missing catalogued].include?(e.status) }

  private

  def fetch
    Rails.cache.fetch("isfdb/series/#{@isfdb_id}/volumes", expires_in: 1.day, skip_nil: true) { ::Isfdb::Client.new.series_volumes(@isfdb_id) }
  rescue ::Isfdb::Client::ServiceError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.warn("series volumes #{@isfdb_id}: #{e.class}: #{e.message}")
    nil
  end

  # Before the series is tied to ISFDB: the one ISFDB series its books'
  # printings all name.
  def inferred_isfdb_id
    ids = ProviderEdition.where(provider: "isfdb", work_id: @series.work_series.select(:work_id)).where.not(series_id: nil).distinct.pluck(:series_id)
    ids.first if ids.one?
  end

  def from_volume(v)
    return if v["language"].present? && !AddBook::EditionCards::ENGLISH.include?(v["language"].downcase)

    title_id = v["external_id"].to_i
    Entry.new(title_id:, position: v["position"].to_d.nonzero?, title: v["title"], authors: Array(v["authors"]),
              year: v["release_date"].to_s[/\A\d{4}/]&.to_i, cover_url: v["cover_url"].to_s.split("|").first.presence,
              work: works_by_title_id[title_id.to_s])
  end

  def works_by_title_id
    @works_by_title_id ||= WorkIdentifier.where(id_type: "isfdb_title").includes(work: WorksController::LIST_INCLUDES)
                                         .where(work_id: Work.select(:id)).to_h { |i| [ i.value, i.work ] }
  end

  def status_of(entry)
    return :missing unless entry.work

    statuses = entry.work.statuses
    return :owned if statuses.include?(:owned)
    return :wanted if statuses.include?(:wanted)

    :catalogued
  end
end

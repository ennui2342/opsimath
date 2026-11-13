# A list as Mark sees it on its page (docs/LISTS.md): each entry with the
# book in the catalogue it is, if any — by ISFDB title, or for an entry
# not matched to ISFDB, by title and author surname — and where it stands
# for him, like SeriesVolumes.
class BookListView
  Entry = Struct.new(:entry, :work, :status, keyword_init: true) do
    delegate :year, :position, :title, :author, :isfdb_title_id, :winner?, to: :entry
    def read? = work&.statuses&.include?(:read)
  end
  # status: :owned | :wanted | :catalogued (in the catalogue, neither) | :missing

  attr_reader :list, :entries

  def self.for(list, scope: "shortlist", from_year: nil) = new(list).tap { |v| v.load(scope:, from_year:) }

  def initialize(list)
    @list = list
  end

  def load(scope:, from_year:)
    rows = @list.entries.to_a.select { |e| e.in_scope?(scope) && (from_year.nil? || e.year.nil? || e.year >= from_year) }
    by_title = works_by_title_id(rows.filter_map(&:isfdb_title_id))
    loose = works_by_name(rows.reject(&:isfdb_title_id).map { |e| name_key(e.title, e.author) })
    @entries = rows.map do |e|
      work = (by_title[e.isfdb_title_id.to_s] if e.isfdb_title_id) || loose[name_key(e.title, e.author)]
      Entry.new(entry: e, work:, status: status_of(work))
    end
    self
  end

  def read = entries.count(&:read?)
  def owned = entries.count { |e| e.status == :owned }
  def missing = entries.select { |e| %i[missing catalogued].include?(e.status) }

  # Award lists: the years, latest first, each with its winner first.
  def by_year = entries.group_by(&:year).sort_by { |y, _| -(y || 0) }.map { |y, es| [ y, es.sort_by { |e| e.winner? ? 0 : 1 } ] }

  private

  def works_by_title_id(ids)
    return {} if ids.empty?

    rows = WorkIdentifier.where(id_type: "isfdb_title", value: ids.map(&:to_s)).pluck(:value, :work_id)
    works = Work.includes(WorksController::CARD_INCLUDES).where(id: rows.map(&:last)).index_by(&:id)
    rows.to_h { |value, work_id| [ value, works[work_id] ] }
  end

  # Plain columns to match on, then only the matches loaded as cards (the
  # web pod has 768 MB).
  def works_by_name(wanted)
    return {} if wanted.empty?

    wanted = wanted.to_set
    keys = WorkContributor.joins(:work, :contributor).where(role: "author").pluck("works.id", "works.title", "contributors.name")
                          .each_with_object({}) do |(id, title, name), out|
                            k = name_key(title, name)
                            out[k] ||= id if wanted.include?(k)
                          end
    works = Work.includes(WorksController::CARD_INCLUDES).where(id: keys.values.uniq).index_by(&:id)
    keys.transform_values { |id| works[id] }
  end

  def name_key(title, author)
    surname = author.to_s.split(/,| and | & /).first.to_s.split.last.to_s
    [ WorkMatcher.key(WorkMatcher.short(title.to_s)), I18n.transliterate(surname).downcase ]
  end

  def status_of(work)
    return :missing unless work

    statuses = work.statuses
    return :owned if statuses.include?(:owned)
    return :wanted if statuses.include?(:wanted)

    :catalogued
  end
end

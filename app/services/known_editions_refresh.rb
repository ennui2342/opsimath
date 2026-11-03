# Fills ProviderEdition with the editions one provider knows for each
# catalogued work, and records the provider's id for the work as a
# WorkIdentifier (docs/CATALOG.md, "Architecture review", "Providers").
# Run once per provider with the :known_editions capability.
#
# A thread pool for the provider calls, persisted afterwards, bounded by a
# wall-clock deadline; whatever a truncated run didn't reach is still due
# next time. A work is re-queried when the provider has never been asked,
# after max_age, or when the work's own ISBNs change; a provider failure
# leaves it due. Rows are upserted by (work, provider, provider_id), so an
# edition keeps its row id across refreshes; other providers' rows are
# never touched.
class KnownEditionsRefresh
  # Per-provider pacing. Open Library's client spaces every request a
  # second apart, so one thread; a first pass over the catalogue takes a
  # few nights, after which only due works are fetched.
  SETTINGS = {
    "isfdb" => { pool_size: 6, deadline: 15.minutes, max_age: 7.days },
    "openlibrary" => { pool_size: 1, deadline: 30.minutes, max_age: 30.days }
  }.freeze
  # Works a provider found nothing for before ISFDB's title + author
  # fallback (2026-11-03) are asked again on the next run rather than
  # waiting out max_age. Self-expiring: every refresh after it is newer.
  TITLE_FALLBACK_SINCE = Time.utc(2026, 11, 3, 22).freeze
  UPDATED_COLUMNS = %i[isbn13 isbn10 title publisher binding publish_date language page_count cover_url cover_artist updated_at].freeze

  Result = Struct.new(:provider, :works, :due, :refreshed, :truncated, keyword_init: true) do
    def to_s = "#{provider}: works=#{works} due=#{due} refreshed=#{refreshed}#{' TRUNCATED' if truncated}"
  end

  def self.run(provider:, **) = new(provider:, **).run

  def self.run_all = Providers.with(:known_editions).map { |provider| run(provider:) }

  # One work, now, from every provider, due or not — a book just wanted, so
  # its bargain-hunting page isn't empty until the night.
  def self.refresh_work(work)
    work = Work.includes(:want, { work_contributors: :contributor }, editions: :edition_identifiers).find(work.id)
    Providers.with(:known_editions).each { |provider| new(provider:).refresh_one(work) }
  end

  def refresh_one(work)
    isbns = source_isbns(work)
    ids = WorkIdentifier.where(work:, id_type: @id_type).pluck(:value)
    known = fetch(work, isbns, ids)
    persist(work, known, isbns) if known
  end

  def initialize(provider:, **overrides)
    @provider = provider
    settings = SETTINGS.fetch(provider.name).merge(overrides)
    @pool_size, @deadline, @max_age = settings.values_at(:pool_size, :deadline, :max_age)
    @id_type = provider.class::WORK_ID_TYPE
  end

  def run
    works = Work.includes(:want, { work_contributors: :contributor }, editions: :edition_identifiers).to_a
    isbns_by_id = works.to_h { |w| [ w.id, source_isbns(w) ] }
    refreshes = ProviderEditionRefresh.where(provider: @provider.name).index_by(&:work_id)
    ids_by_work = WorkIdentifier.where(id_type: @id_type).pluck(:work_id, :value).group_by(&:first).transform_values { |v| v.map(&:last) }
    found = ProviderEdition.where(provider: @provider.name).distinct.pluck(:work_id).to_set
    due = works.select do |w|
      r = refreshes[w.id]
      r.nil? || r.refreshed_at < @max_age.ago || r.queried_isbns.sort != isbns_by_id[w.id].sort ||
        (r.refreshed_at < TITLE_FALLBACK_SINCE && !found.include?(w.id))
    end

    fetched = Concurrent::Hash.new
    started = Time.current
    pool = Concurrent::FixedThreadPool.new(@pool_size)
    due.each do |work|
      pool.post do
        next if Time.current - started > @deadline # past the deadline: leave the rest due

        known = fetch(work, isbns_by_id[work.id], ids_by_work[work.id] || [])
        fetched[work.id] = known if known
      end
    end
    pool.shutdown
    truncated = !pool.wait_for_termination(@deadline + 2.minutes) || fetched.size < due.size
    pool.kill unless pool.shutdown?

    works_by_id = due.index_by(&:id)
    fetched.each { |id, known| persist(works_by_id.fetch(id), known, isbns_by_id.fetch(id)) }
    Rails.logger.warn("known editions refresh (#{@provider.name}): #{due.size - fetched.size} works left for next run") if truncated
    Result.new(provider: @provider.name, works: works.size, due: due.size, refreshed: fetched.size, truncated:)
  end

  private

  # The work's own ISBNs, ISBN-13 first, then those it was wanted under —
  # a wanted book has no edition of its own until one is owned.
  def source_isbns(work)
    own = work.editions.flat_map(&:edition_identifiers)
              .select { |i| i.id_type == "isbn13" || i.id_type == "isbn10" }
              .sort_by { |i| i.id_type == "isbn13" ? 0 : 1 }
              .map(&:value)
    (own + Array(work.want&.seed_isbns)).uniq
  end

  # Providers::KnownEditions, or nil on a provider failure (left due).
  # The title and first author let a provider look the work up when it
  # has no ISBN to go on (Providers::Isfdb's title fallback).
  def fetch(work, isbns, work_ids)
    @provider.known_editions(isbns:, work_ids:, title: work.title, author: work.authors.first&.name)
  rescue StandardError => e
    Rails.logger.warn("known editions refresh (#{@provider.name}): work ##{work.id} — #{e.class}: #{e.message}")
    nil
  end

  def persist(work, known, isbns)
    now = Time.current
    rows = known.editions.map { |e| row(work, e, now) }.uniq { |r| r[:provider_id] }

    ProviderEdition.transaction do
      if rows.any?
        ProviderEdition.upsert_all(rows, unique_by: [ :work_id, :provider, :provider_id ],
                                         update_only: UPDATED_COLUMNS, record_timestamps: false)
      end
      work.provider_editions.where(provider: @provider.name).where.not(provider_id: rows.map { |r| r[:provider_id] }).delete_all
      known.work_ids.each do |value|
        work.work_identifiers.find_or_create_by!(id_type: @id_type, value:) { |i| i.source = "isbn_lookup" }
      end
      ProviderEditionRefresh.upsert({ work_id: work.id, provider: @provider.name, refreshed_at: now, queried_isbns: isbns },
                                    unique_by: [ :work_id, :provider ])
    end
  end

  def row(work, edition, now)
    {
      work_id: work.id, provider: @provider.name, provider_id: edition.id,
      isbn13: edition.isbn13, isbn10: edition.isbn10, title: edition.title, publisher: edition.publisher,
      binding: edition.binding, publish_date: edition.publish_date, language: edition.language,
      page_count: edition.page_count, cover_url: edition.cover_url, cover_artist: edition.cover_artist,
      created_at: now, updated_at: now
    }
  end
end

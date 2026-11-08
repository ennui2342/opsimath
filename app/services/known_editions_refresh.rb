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
  # A book a provider hasn't found is asked again weekly whatever its
  # max_age — so one a provider adds later is picked up then.
  UNLINKED_RETRY = 7.days
  CROSS_ISBNS = 5
  # Works a provider found nothing for before the lookup last improved are
  # asked again on the next run rather than waiting out their retry —
  # bump it when lookups get better. Self-expiring: every refresh after it
  # is newer. 2026-11-03 title + author matching; 2026-11-08 ISFDB's single
  # publication for anthologies, nonfiction and magazines.
  TITLE_FALLBACK_SINCE = Time.utc(2026, 11, 8, 12).freeze
  UPDATED_COLUMNS = %i[isbn13 isbn10 title publisher binding publish_date language page_count cover_url cover_artist
                       pub_series_id pub_series_name pub_series_num updated_at].freeze

  Result = Struct.new(:provider, :works, :due, :refreshed, :truncated, keyword_init: true) do
    def to_s = "#{provider}: works=#{works} due=#{due} refreshed=#{refreshed}#{' TRUNCATED' if truncated}"
  end

  def self.run(provider:, **) = new(provider:, **).run

  def self.run_all = Providers.with(:known_editions).map { |provider| run(provider:) }

  # One work, now, from every provider, due or not — a book just wanted, so
  # its bargain-hunting page isn't empty until the night.
  def self.refresh_work(work)
    work = Work.includes(:want, :provider_editions, { work_contributors: :contributor }, editions: :edition_identifiers).find(work.id)
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
    works = Work.includes(:want, :provider_editions, { work_contributors: :contributor }, editions: :edition_identifiers).to_a
    isbns_by_id = works.to_h { |w| [ w.id, source_isbns(w) ] }
    refreshes = ProviderEditionRefresh.where(provider: @provider.name).index_by(&:work_id)
    ids_by_work = WorkIdentifier.where(id_type: @id_type).pluck(:work_id, :value).group_by(&:first).transform_values { |v| v.map(&:last) }
    found = ProviderEdition.where(provider: @provider.name).distinct.pluck(:work_id).to_set
    due = works.select do |w|
      r = refreshes[w.id]
      r.nil? || r.refreshed_at < @max_age.ago || r.queried_isbns.sort != isbns_by_id[w.id].sort ||
        (!found.include?(w.id) && (r.refreshed_at < UNLINKED_RETRY.ago || r.refreshed_at < TITLE_FALLBACK_SINCE))
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
  # a wanted book has no edition of its own until one is owned — then a few
  # that *other* providers have given for it: a book Open Library found is
  # one ISFDB can now find by ISBN, and the other way round. Only English
  # printings of the book itself (not an omnibus containing it, not a
  # translation, which would identify a different record), and few
  # (CROSS_ISBNS): a provider tries them one at a time.
  def source_isbns(work)
    own = work.editions.flat_map(&:edition_identifiers)
              .select { |i| i.id_type == "isbn13" || i.id_type == "isbn10" }
              .sort_by { |i| i.id_type == "isbn13" ? 0 : 1 }
              .map(&:value)
    title = WorkMatcher.key(WorkMatcher.short(work.title))
    cross = work.provider_editions
                .select { |e| e.provider != @provider.name && WorkMatcher.english_language?(e.language) }
                .select { |e| WorkMatcher.key(WorkMatcher.short(e.title)) == title }
                .filter_map(&:isbn).uniq.first(CROSS_ISBNS)
    (own + Array(work.want&.seed_isbns) + cross).uniq
  end

  # Providers::KnownEditions, or nil on a provider failure (left due). By
  # stored id or ISBN first; when that finds nothing, by title and author
  # — the provider's own search, WorkMatcher deciding what matches.
  def fetch(work, isbns, work_ids)
    known = @provider.known_editions(isbns:, work_ids:)
    return known if known.editions.any? || known.work_ids.any? || work.title.blank?

    by_title(work) || known
  rescue StandardError => e
    Rails.logger.warn("known editions refresh (#{@provider.name}): work ##{work.id} — #{e.class}: #{e.message}")
    nil
  end

  def by_title(work)
    return unless @provider.capabilities.include?(:search_works)

    author = work.authors.first&.name
    matches = WorkMatcher.match(@provider.search_works(title: work.title, author:, complete: true), title: work.title, author:)
    return if matches.empty?

    # ISFDB's search carries each title's printings; Open Library's lists
    # works, whose editions are a further call.
    editions = matches.flat_map { |m| Array(m.editions) }
    editions = matches.flat_map { |m| @provider.known_editions(isbns: [], work_ids: [ m.id ]).editions } if editions.empty?
    Providers::KnownEditions.new(work_ids: matches.map(&:id), editions: editions.uniq(&:id))
  end

  def collecting = @collecting ||= CollectingProfile.current

  def newsworthy?(printing, wanted)
    return false unless printing.physical?
    return false if printing.book_club? && collecting.exclude_book_clubs

    wanted || (printing.year.present? && printing.year >= Date.current.year - 1)
  end

  def persist(work, known, isbns)
    now = Time.current
    rows = known.editions.map { |e| row(work, e, now) }.uniq { |r| r[:provider_id] }
    had_ids = work.provider_editions.where(provider: @provider.name).pluck(:provider_id)
    had_links = work.work_identifiers.where(id_type: @id_type).pluck(:value)

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
    record_events(work, known.work_ids - had_links, had_ids.empty? ? [] : rows.reject { |r| had_ids.include?(r[:provider_id]) })
  end

  # For #catalogue's morning digest: a book newly linked to this provider,
  # and new printings of a book it already knew — not a first fill, which
  # the link already says. Only printings worth hearing about: for a wanted
  # book, any physical, non-book-club printing (a new cover to hunt); for
  # the rest, one from this year or last (a new edition out). A provider's
  # list growing with older printings — ISFDB cataloguing a 1972 Ace, or a
  # fuller lookup — is stored silently (2026-11-08: the first digest
  # announced "411 new printings across 96 books", nearly all old).
  PROVIDER_LABELS = { "isfdb" => "ISFDB", "openlibrary" => "Open Library" }.freeze

  def record_events(work, new_links, new_rows)
    label = PROVIDER_LABELS.fetch(@provider.name, @provider.name)
    wanted = work.want.present?
    if new_links.any?
      CatalogueEvent.record(kind: "linked", origin: "known_editions", work:, details: { provider: @provider.name, wanted: },
                            summary: "#{work.title} found in #{label}")
    end
    new_rows = new_rows.select { |r| newsworthy?(ProviderEdition.new(r.except(:created_at, :updated_at)), wanted) }
    return if new_rows.empty?

    printings = new_rows.map { |r| [ r[:publisher], r[:publish_date].to_s[0, 4].presence ].compact.join(" ") }.uniq
    CatalogueEvent.record(kind: "new_printings", origin: "known_editions", work:,
                          details: { provider: @provider.name, wanted:, count: new_rows.size, printings:,
                                     provider_ids: new_rows.map { |r| r[:provider_id] } },
                          summary: "#{work.title}: #{new_rows.size} new #{'printing'.pluralize(new_rows.size)} in #{label} (#{printings.first(3).join(', ')})")
  end

  def row(work, edition, now)
    {
      work_id: work.id, provider: @provider.name, provider_id: edition.id,
      isbn13: edition.isbn13, isbn10: edition.isbn10, title: edition.title, publisher: edition.publisher,
      binding: edition.binding, publish_date: edition.publish_date, language: edition.language,
      page_count: edition.page_count, cover_url: edition.cover_url, cover_artist: edition.cover_artist,
      pub_series_id: edition.pub_series_id, pub_series_name: edition.pub_series_name, pub_series_num: edition.pub_series_num,
      created_at: now, updated_at: now
    }
  end
end

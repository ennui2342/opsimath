# Keeps each edition up to date from the printing it's anchored to
# (docs/CATALOG.md, "Anchored editions", build step 3). An edition's anchor
# is its ISFDB publication — an `isfdb` EditionIdentifier, else the single
# ISFDB printing its ISBN identifies, even for an edition already on Open
# Library (ISFDB is the trusted source: a book added from Open Library
# moves to ISFDB once ISFDB's printing is known — Continuum 4, 2026-11-08)
# — else its Open Library edition, by identifier or a unique ISBN. The anchor's record is read from
# ProviderEdition (KnownEditionsRefresh keeps it current), so this makes no
# network calls.
#
# Per field, against the anchor:
#   :same            nothing to do
#   :fill            empty on the edition — take the anchor's value
#   :update          the value came from the anchor's provider, which now says otherwise
#   :replace         it came from another provider (Goodreads) or no recorded
#                    source, and the anchor says otherwise — the anchor wins,
#                    when its provider is TRUSTED (ISFDB)
#   :keep            the same, from a provider that isn't trusted to overrule
#                    (Open Library: group names for imprints, exact-day dates,
#                    guessed formats — no better than what's there)
#   :manual          Mark's own value — never touched
#   :anchor_blank    the anchor has nothing — the edition's value stays
# Then, for fields still empty, other providers' records of the same
# printing (a unique shared ISBN) can fill them (:secondary_fill).
#
# Editions whose printing is in question — a pending printing choice, or a
# decision flagged "looks like a different printing" — are held: refreshing
# them from a wrong anchor would make things worse.
#
# `plan` is a dry run; `apply` does it (nightly, AnchoredRefreshJob): the
# anchor recorded on an edition anchored by ISBN, the fields written with
# the provider as their source, the cover downloaded, the provider's record
# of the edition kept current, and one #catalogue event per edition.
class AnchoredRefresh
  FieldPlan = Struct.new(:field, :action, :current, :proposed, :source, keyword_init: true)
  EditionPlan = Struct.new(:edition, :work, :anchor_status, :anchor, :fields, :secondary, keyword_init: true)
  # anchor_status: :anchored | :by_isbn (would be anchored now) | :held | :missing_record | :ambiguous | :unanchored

  FIELDS = %i[publisher publish_date page_count language cover_artist format format_detail].freeze
  TRUSTED = %w[isfdb].freeze
  WRITES = %i[fill update replace secondary_fill].freeze
  ANCHOR_TYPES = %w[isfdb openlibrary].freeze

  def self.plan(editions = default_scope) = new.plan(editions)

  def self.default_scope
    Edition.includes(:edition_identifiers, { cover_image_attachment: :blob }, works: :provider_editions)
  end

  def plan(editions)
    held = held_edition_ids
    editions.find_each.map { |edition| plan_edition(edition, held) }
  end

  def self.apply(editions = default_scope) = new.apply(editions)

  # -> number of editions changed
  def apply(editions)
    plan(editions).count { |p| apply_edition(p) }
  end

  private

  APPLIABLE = %i[anchored by_isbn].freeze

  def apply_edition(plan)
    return false unless APPLIABLE.include?(plan.anchor_status)

    writes = plan.fields.select { |f| WRITES.include?(f.action) } + plan.secondary
    return false if writes.empty? && plan.anchor_status == :anchored

    edition, anchor = plan.edition, plan.anchor
    Edition.transaction do
      edition.edition_identifiers.find_or_create_by!(id_type: anchor.provider, value: anchor.provider_id) if plan.anchor_status == :by_isbn
      changed = writes.filter_map { |f| write(edition, f, f.action == :secondary_fill ? f.source : anchor.provider) }
      remember(edition, anchor)
      PendingDecisionSweep.for_edition(edition.id)
      record_event(plan, changed) if changed.any?
      changed.any?
    end
  end

  # -> the field written, or nil (a cover that couldn't be downloaded)
  def write(edition, plan, provider)
    if plan.field == :cover_image
      data = HasCoverImage.fetch_image(plan.proposed) or return
      edition.cover_image.attach(**data)
      edition.update!(field_sources: edition.field_sources.merge("cover_image" => provider))
    else
      edition.update!(plan.field => plan.proposed, field_sources: edition.field_sources.merge(plan.field.to_s => provider))
    end
    plan.field
  end

  # The provider's record of this edition (EnrichmentRecord), as the
  # anchor now says — the cog compares against it, and the next run's
  # cover check reads its cover_url.
  #
  # Merged, not replaced: an ISFDB record keeps isfdb-adapter's raw shape,
  # which other code re-reads (IsfdbEditionEnricher.reprocess).
  def remember(edition, anchor)
    record = EnrichmentRecord.find_or_initialize_by(entity: edition, provider: anchor.provider)
    raw = record.raw_payload.presence || anchor.attributes.slice(*%w[provider_id isbn13 isbn10 title publisher binding publish_date language page_count cover_artist])
    record.update!(external_id: anchor.provider_id, fetched_at: Time.current,
                   raw_payload: raw.merge("cover_url" => anchor.cover_url),
                   fields: record.fields.merge(proposals(anchor).except(:cover_image).compact.transform_keys(&:to_s)))
  end

  LABELS = { "isfdb" => "ISFDB", "openlibrary" => "Open Library" }.freeze

  def record_event(plan, fields)
    names = fields.map { |f| f == :cover_image ? "cover" : f.to_s.humanize(capitalize: false) }
    CatalogueEvent.record(kind: "refreshed", origin: "anchored_refresh", work: plan.work,
                          details: { provider: plan.anchor.provider, fields: fields.map(&:to_s), anchored_now: plan.anchor_status == :by_isbn },
                          summary: "#{CatalogueEvent.title(plan.work)}: #{names.to_sentence} from #{LABELS.fetch(plan.anchor.provider, plan.anchor.provider)}")
  end

  def held_edition_ids
    PendingDecision.pending.where("payload->>'entity_type' = 'Edition'")
                   .where("kind = 'enrichment_printing_choice' OR payload ? 'identity_question'")
                   .pluck(Arel.sql("payload->>'entity_id'")).map(&:to_i).to_set
  end

  def plan_edition(edition, held)
    work = edition.works.first
    known = work ? work.provider_editions.to_a : []
    base = { edition:, work:, fields: [], secondary: [] }
    return EditionPlan.new(**base, anchor_status: :held) if held.include?(edition.id)

    status, anchor = find_anchor(edition, known)
    return EditionPlan.new(**base, anchor_status: status) unless anchor

    fields = compare(edition, anchor)
    EditionPlan.new(**base, anchor_status: status, anchor:, fields:, secondary: secondary_fills(edition, anchor, known, fields))
  end

  # Per provider, most trusted first: its identifier, else a unique ISBN
  # match. Two ISFDB printings on one ISBN is a question for Mark (the
  # printing choice), so it's :ambiguous — unless the edition is already
  # on Open Library, which then stays its anchor meanwhile.
  def find_anchor(edition, known)
    ids = edition.edition_identifiers.select { |i| ANCHOR_TYPES.include?(i.id_type) }
    isbn = isbn_of(edition)
    on_open_library = ids.any? { |i| i.id_type == "openlibrary" }
    ANCHOR_TYPES.each do |provider|
      if (id = ids.find { |i| i.id_type == provider }&.value)
        row = known.find { |r| r.provider == provider && r.provider_id == id }
        return [ :anchored, row ] if row
        return [ :missing_record, nil ] if provider == "isfdb" # linked, but its record isn't on file yet
      end
      next unless isbn

      matches = known.select { |r| r.provider == provider && r.isbn == isbn }
      return [ :by_isbn, matches.first ] if matches.one?
      return [ :ambiguous, nil ] if matches.size > 1 && provider == "isfdb" && !on_open_library
    end
    [ :unanchored, nil ]
  end

  def isbn_of(edition)
    ids = edition.edition_identifiers
    ids.find { |i| i.id_type == "isbn13" }&.value || ids.find { |i| i.id_type == "isbn10" }&.value&.then { |v| Isbn.to_13(v) }
  end

  def proposals(row)
    AddBook::Create.fields(AddBook::EditionCards.from_provider_editions([ row ]).first)
  end

  def compare(edition, anchor)
    proposed = proposals(anchor)
    plans = FIELDS.map do |field|
      current, value = edition.public_send(field), proposed[field]
      source = edition.field_sources[field.to_s]
      action =
        if value.blank? then current.blank? ? :same : :anchor_blank
        elsif current.blank? then :fill
        elsif current.to_s.strip == value.to_s.strip then :same
        elsif source == "manual" then :manual
        elsif source == anchor.provider then :update
        elsif TRUSTED.include?(anchor.provider) then :replace
        else :keep
        end
      FieldPlan.new(field:, action:, current:, proposed: value, source:)
    end
    plans << cover_plan(edition, anchor, proposed[:cover_image])
  end

  # The cover: fill when there's none; an update when the anchor's cover
  # image has changed since it was taken (its URL differs from the one on
  # the provider's record of this edition).
  def cover_plan(edition, anchor, url)
    taken = EnrichmentRecord.where(entity: edition, provider: anchor.provider).pick(:raw_payload)&.then { |r| r["cover_url"].to_s.split("|").first }
    action =
      if url.blank? then :same
      elsif !edition.cover_image.attached? then :fill
      elsif edition.field_sources["cover_image"] == "manual" then :manual
      elsif taken.present? && taken != url then :update
      else :same
      end
    FieldPlan.new(field: :cover_image, action:, current: taken, proposed: url, source: edition.field_sources["cover_image"])
  end

  def secondary_fills(edition, anchor, known, plans)
    still_empty = FIELDS.select { |f| edition.public_send(f).blank? && plans.find { |p| p.field == f }&.proposed.blank? }
    return [] if still_empty.empty? || anchor.isbn.blank?

    others = known.select { |r| r.provider != anchor.provider && r.isbn == anchor.isbn }
    return [] unless others.one?

    values = proposals(others.first)
    still_empty.filter_map { |f| FieldPlan.new(field: f, action: :secondary_fill, proposed: values[f], source: others.first.provider) if values[f].present? }
  end
end

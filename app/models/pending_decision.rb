class PendingDecision < ApplicationRecord
  enum :status, { pending: "pending", accepted: "accepted", rejected: "rejected" }

  validates :kind, presence: true

  # enrichment_printing_choice only: each candidate ISFDB printing's cover,
  # downloaded server-side at raise time (ISFDB's wiki cover URLs
  # Cloudflare-gate hotlinked <img> loads) and keyed by pub id
  # ("<pub_id>.jpg"), so the review screen shows real images — same as the
  # enrichment_conflict flow's EnrichmentRecord cover. Purged on resolve.
  has_many_attached :candidate_covers

  def candidate_cover(pub_id)
    candidate_covers.find { |attachment| attachment.filename.base == pub_id.to_s }
  end

  # Display shape for the 3-card review screen — one card for the Edition's
  # current catalog state, one per other known provider (info only), and one
  # for the record that actually raised this decision (actionable —
  # checkboxes on whatever's in payload["fields"]). The structs are the
  # component's: EditionReconciliation feeds the same component the same
  # shapes (see docs/DESIGN_SYSTEM.md, "Comparison-review screen").
  Card = Ui::ComparisonCardComponent::Card
  FieldRow = Ui::ComparisonCardComponent::FieldRow

  # Display order for the fields any known provider can propose on an
  # Edition — mirrors the field set Enrichment::IsfdbEditionEnricher and
  # Enrichment::SourceRecorder callers actually populate. cover_image is
  # handled separately (an attachment, not a plain field).
  EDITION_FIELD_ORDER = %w[format format_detail publisher publish_date language page_count].freeze

  ID_TYPE_LABELS = { "isbn10" => "ISBN-10", "isbn13" => "ISBN-13", "isfdb" => "ISFDB", "goodreads" => "Goodreads" }.freeze

  # entity_type/entity_id live inside the jsonb payload, not real
  # columns — so this is a plain lookup, not a Rails polymorphic
  # association. The enrichment kinds carry them; the Goodreads-sync
  # kinds (reread_conflict, possible_duplicate_work) don't — they point
  # at a work/edition by loose id and carry a plain `title` instead.
  def entity
    payload["entity_type"]&.constantize&.find_by(id: payload["entity_id"])
  end

  # A one-line label for the review-queue list — the book this decision
  # is about, whatever its kind. Falls back through: the entity Edition's
  # work titles, the payload's own `title` (Goodreads-sync kinds), then a
  # generic placeholder.
  def display_title
    record = entity
    return record.works.map(&:title).join(", ").presence || "Edition ##{record.id}" if record.is_a?(Edition)

    payload["title"].presence || "Untitled #{kind}"
  end

  # Display-shaped view derived live from payload["fields"] (a plain
  # array of field-name strings — one shape for every enrichment_conflict
  # decision, whether it's a single field or a whole fetch bundled
  # together, they differ only in how many names are listed) plus
  # whatever the named source's latest EnrichmentRecord currently says.
  # Not a frozen snapshot: see Enrichment::SourceRecorder.create_bundled_decision
  # for why. [] for a kind whose payload doesn't carry field-level data
  # at all (e.g. reread_conflict).
  def field_diffs
    return [] unless payload["fields"]

    record = entity
    latest = record && EnrichmentRecord.latest(entity: record, provider: payload["source"])

    payload["fields"].map do |field|
      next { field: field, current: nil, proposed: nil, source: payload["source"] } if field == "cover_image"

      # A non-cover field names a real conflict — if no matching
      # EnrichmentRecord can be found, that's a genuine bug (source-name
      # mismatch, missing fields data, deleted entity), not "nothing to
      # propose." Raise rather than silently return nil: a silent nil
      # here would get filtered out by accept_enrichment's presence
      # check, the decision would still get marked "accepted," and the
      # field would never actually apply — worse than an exception,
      # since nothing would signal the failure.
      raise "no #{payload["source"]} EnrichmentRecord found for #{payload["entity_type"]}##{payload["entity_id"]}, field #{field}" unless latest

      { field: field, current: record.public_send(field), proposed: latest.fields[field], source: payload["source"] }
    end
  end

  # Purely additive, display-only: what every known source currently
  # says for one field — one row per provider (EnrichmentRecord's own
  # uniqueness guarantees that now, so no per-provider "latest of many"
  # dedup is needed here anymore). Informs a review (e.g. seeing that two
  # sources actually agree and only a third disagrees) but never drives
  # accept/reject — that stays field_diffs' job. N-way from day one: the
  # moment a third provider's EnrichmentRecord exists for this entity, it
  # shows up here with zero further code changes.
  def field_candidates(field_name)
    return [] unless entity

    entity.enrichment_records.filter_map do |record|
      value = record.fields[field_name.to_s]
      { provider: record.provider, value: value, fetched_at: record.fetched_at } if value.present?
    end
  end

  # nil for anything that isn't a field-comparison decision on a real
  # Edition (e.g. reread_conflict, or a decision whose named source has no
  # backing EnrichmentRecord at all — a genuine data problem, but this is a
  # display path, not accept/reject, so it degrades to the plain "no
  # automatic action" fallback rather than raising the way field_diffs does).
  def comparison_cards
    record = entity
    return nil unless record.is_a?(Edition) && payload["fields"]

    proposing_record = EnrichmentRecord.latest(entity: record, provider: payload["source"])
    return nil unless proposing_record

    other_providers = record.enrichment_records.where.not(provider: payload["source"]).distinct.pluck(:provider)

    { edition: edition_card(record), others: other_providers.map { |p| provider_card(record, p) }, proposed: proposed_card(record, proposing_record) }
  end

  # Display shape for the enrichment_printing_choice screen: the Edition's
  # current state (reference), then one card per ISFDB printing that
  # shares the ISBN. Each candidate card carries a radio in its header
  # ("this is my printing") and per-field checkboxes; only the picked
  # card's checkboxes submit (Stimulus printing-choice / #fields_disabled).
  def printing_choice_cards
    record = entity
    return nil unless kind == "enrichment_printing_choice" && record.is_a?(Edition)

    candidates = payload["candidates"] || []
    { edition: edition_card(record), candidates: candidates.each_with_index.map { |c, i| candidate_card(c, first: i.zero?) } }
  end

  private

  def candidate_card(candidate, first:)
    pub_id = candidate["_isfdb_pub_id"].to_s
    format, format_detail = Enrichment::IsfdbEditionEnricher::FORMAT_BY_PTYPE[candidate["binding"].to_s.downcase]
    cover = candidate_cover(pub_id)

    rows = {
      "format" => format&.humanize, "format_detail" => format_detail&.humanize,
      "publisher" => candidate["publisher"], "publish_date" => candidate["publish_date"],
      "language" => candidate["language"], "page_count" => candidate["page_count"]
    }.filter_map { |name, value| FieldRow.new(name: name, value: value, selectable: true) if value.present? }

    Card.new(
      label: [ "ISFDB", candidate["publish_date"].to_s[0, 4].presence, candidate["publisher"].presence ].compact.join(" · "),
      fields: rows,
      cover: cover, cover_selectable: cover.present?,
      select_name: "pub_id", select_value: pub_id, selected: first,
      input_scope: "pub#{pub_id}_", fields_disabled: !first
    )
  end

  def edition_card(record)
    fields = EDITION_FIELD_ORDER.map do |field|
      FieldRow.new(name: field, value: format_field(field, record.public_send(field)), chip: record.field_sources[field], selectable: false)
    end
    identifiers = record.edition_identifiers.map { |i| [ ID_TYPE_LABELS.fetch(i.id_type, i.id_type.upcase), i.value ] }

    Card.new(label: "Edition · in catalog", proposed: false, cover: record.cover_image, cover_selectable: false,
             show_empty_cover: true, fields: fields, identifiers: identifiers)
  end

  # One EnrichmentRecord per (edition, provider) now (see
  # EnrichmentRecord's own uniqueness), so this always reflects that
  # provider's full current picture — a partial fetch (RSS's cover-only
  # touch, say) merges into the same record CSV import's text fields
  # already populated, rather than leaving them stranded on a separate,
  # no-longer-latest row the way this used to.
  def provider_card(edition, provider)
    source_record = EnrichmentRecord.latest(entity: edition, provider: provider)
    fields = EDITION_FIELD_ORDER.select { |field| source_record.fields.key?(field) }.map do |field|
      FieldRow.new(name: field, value: format_field(field, source_record.fields[field]), selectable: false)
    end

    Card.new(label: "#{provider.humanize} · on file", meta: source_record.fetched_at, proposed: false,
             cover: source_record.cover_image, cover_selectable: false, show_empty_cover: false, fields: fields,
             info_note: "Reference only — not part of this decision.")
  end

  def proposed_card(record, source_record)
    disputed = payload["fields"]
    fields = EDITION_FIELD_ORDER.select { |field| source_record.fields.key?(field) }.map do |field|
      FieldRow.new(name: field, value: format_field(field, source_record.fields[field]), selectable: disputed.include?(field))
    end
    cover_selectable = disputed.include?("cover_image") && source_record.cover_image.attached?

    Card.new(label: "#{payload["source"].humanize} · proposed", meta: source_record.fetched_at, proposed: true,
             cover: source_record.cover_image, cover_selectable: cover_selectable, show_empty_cover: false, fields: fields)
  end

  # format/format_detail are enum-style snake_case values ("mass_market")
  # — humanize them for display, same as every field label. Every other
  # field is already a plain string/integer fit to show as-is.
  def format_field(field, value)
    %w[format format_detail].include?(field) ? value&.humanize : value
  end
end

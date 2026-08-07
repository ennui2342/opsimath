class PendingDecision < ApplicationRecord
  enum :status, { pending: "pending", accepted: "accepted", rejected: "rejected" }

  validates :kind, presence: true

  # entity_type/entity_id live inside the jsonb payload, not real
  # columns — so this is a plain lookup, not a Rails polymorphic
  # association. Every kind's payload carries them today (see
  # Enrichment::FieldApplier/IsfdbEditionEnricher).
  def entity
    payload["entity_type"]&.constantize&.find_by(id: payload["entity_id"])
  end

  # Display-shaped view derived live from payload["fields"] (a plain
  # array of field-name strings — identical shape for an isolated
  # enrichment_field_conflict and a bundled enrichment_edition_mismatch,
  # they differ only in how many names are listed) plus whatever the
  # named source's latest EnrichmentRecord currently says. Not a frozen
  # snapshot: see Enrichment::FieldApplier.find_or_create_conflict for
  # why. [] for a kind whose payload doesn't carry field-level data at
  # all (e.g. reread_conflict).
  def field_diffs
    return [] unless payload["fields"]

    record = entity
    latest = record && EnrichmentRecord.where(entity: record, provider: payload["source"]).order(fetched_at: :desc).first

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
  # says for one field, latest fetch per provider. Informs a review (e.g.
  # seeing that two sources actually agree and only a third disagrees)
  # but never drives accept/reject — that stays field_diffs' job. N-way
  # from day one: the moment a third provider's EnrichmentRecord exists
  # for this entity, it shows up here with zero further code changes.
  def field_candidates(field_name)
    return [] unless entity

    entity.enrichment_records
          .select("DISTINCT ON (provider) *")
          .order(:provider, fetched_at: :desc)
          .filter_map do |record|
      value = record.fields[field_name.to_s]
      { provider: record.provider, value: value, fetched_at: record.fetched_at } if value.present?
    end
  end
end

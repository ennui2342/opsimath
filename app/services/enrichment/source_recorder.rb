module Enrichment
  # The one entry point for "a source just supplied some field data for
  # this entity" — deliberately entity-agnostic (Edition today, but nothing
  # here assumes it; a future Work-level source, e.g. Wikidata via
  # PHILOSOPHY.md's own noted future direction, could reuse this
  # unchanged). Creates the durable EnrichmentRecord, then routes every
  # field through the *same* FieldApplier fill/conflict logic ISFDB
  # already uses — this is what makes Goodreads a peer source instead of
  # a privileged writer: on a genuinely new entity every field is blank,
  # so every proposal is a clean :fill (identical to today's observable
  # behavior), but if a source is ever recalled against an entity that
  # already has real data, it goes through the same protection ISFDB's
  # proposals already get, rather than silently overwriting.
  module SourceRecorder
    def self.record(entity:, provider:, external_id:, raw_payload:, fields: {})
      EnrichmentRecord.create!(entity: entity, provider: provider, external_id: external_id, fetched_at: Time.current, raw_payload: raw_payload, fields: fields)
      fields.each { |field, value| FieldApplier.apply(entity, field, value, provider) }
    end
  end
end

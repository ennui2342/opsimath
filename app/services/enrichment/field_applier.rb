module Enrichment
  # The single-valued-field policy from docs/DATA_MODEL.md's
  # EnrichmentRecord section: filling a genuinely empty field applies
  # automatically; overwriting an already-populated one always surfaces a
  # PendingDecision instead, regardless of how confident the provider is.
  # field_sources[field] records which provider currently backs an
  # applied value. (Resetting field_sources to "manual" on a direct edit
  # is a real requirement too, per that same section — deferred until
  # there's an actual manual-edit code path to guard, since none exists
  # yet with no UI built.)
  module FieldApplier
    Result = Struct.new(:status, :pending_decision, keyword_init: true)

    def self.apply(record, field, value, source)
      return Result.new(status: :skipped) if value.blank?

      current = record.public_send(field)

      if current.blank?
        record.update!(field => value, :field_sources => record.field_sources.merge(field.to_s => source))
        return Result.new(status: :applied)
      end

      return Result.new(status: :unchanged) if normalize(current) == normalize(value)

      pending = find_or_create_conflict(record, field, current, value, source)
      Result.new(status: :pending, pending_decision: pending)
    end

    # Case/whitespace/punctuation-insensitive — confirmed against real
    # PendingDecision data that several "conflicts" were never real
    # disagreements at all (e.g. "Newcon Press" vs "NewCon Press", "Pan/
    # Ballantine" vs "Pan / Ballantine"), just two sources formatting the
    # same fact differently.
    def self.normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
    private_class_method :normalize

    def self.find_or_create_conflict(record, field, current, value, source)
      entity_type = record.class.name
      entity_id = record.id

      existing = PendingDecision.where(kind: "enrichment_field_conflict", status: "pending")
                                 .where("payload @> ?", { entity_type: entity_type, entity_id: entity_id, field: field.to_s }.to_json)
                                 .first
      return existing if existing

      PendingDecision.create!(
        kind: "enrichment_field_conflict",
        payload: {
          entity_type: entity_type,
          entity_id: entity_id,
          field: field.to_s,
          current_value: current,
          proposed: [ { "value" => value, "source" => source } ]
        }
      )
    end
    private_class_method :find_or_create_conflict
  end
end

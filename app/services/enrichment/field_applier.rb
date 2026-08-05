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
  #
  # Split into plan (pure — decide what *would* happen, no mutation) and
  # commit (perform it) so a caller enriching several fields at once (see
  # Enrichment::IsfdbEditionEnricher) can look at every field's plan
  # together before committing any of them — e.g. to notice that two
  # fields disagreeing *simultaneously* is a different, stronger signal
  # than either disagreeing alone. `apply` is plan+commit in one step,
  # for simple single-field callers that don't need that.
  module FieldApplier
    Result = Struct.new(:status, :pending_decision, keyword_init: true)
    Plan = Struct.new(:record, :field, :action, :value, :source, :current, keyword_init: true)

    def self.plan(record, field, value, source)
      return Plan.new(action: :skipped) if value.blank?

      current = record.public_send(field)
      return Plan.new(record: record, field: field, action: :fill, value: value, source: source) if current.blank?
      return Plan.new(action: :unchanged) if normalize(current) == normalize(value)

      Plan.new(record: record, field: field, action: :conflict, value: value, source: source, current: current)
    end

    # :fill and :refine commit identically (write the value, record
    # field_sources) — the distinction only matters to the caller
    # deciding *whether* to commit a given plan (see IsfdbEditionEnricher),
    # not to how a decided-safe write is performed.
    def self.commit(plan)
      case plan.action
      when :fill, :refine
        plan.record.update!(plan.field => plan.value, field_sources: plan.record.field_sources.merge(plan.field.to_s => plan.source))
        Result.new(status: :applied)
      when :conflict
        pending = find_or_create_conflict(plan.record, plan.field, plan.current, plan.value, plan.source)
        Result.new(status: :pending, pending_decision: pending)
      else
        Result.new(status: plan.action)
      end
    end

    def self.apply(record, field, value, source)
      commit(plan(record, field, value, source))
    end

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

    # Case/whitespace/punctuation-insensitive — confirmed against real
    # PendingDecision data that several "conflicts" were never real
    # disagreements at all (e.g. "Newcon Press" vs "NewCon Press", "Pan/
    # Ballantine" vs "Pan / Ballantine"), just two sources formatting the
    # same fact differently.
    def self.normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end

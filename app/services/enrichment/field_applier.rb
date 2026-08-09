module Enrichment
  # Pure field-level planning only — deciding *what would happen* to one
  # field, never performing it. The single-valued-field policy from
  # docs/DATA_MODEL.md's EnrichmentRecord section: filling a genuinely
  # empty field is safe; overwriting an already-populated one always
  # needs review, regardless of how confident the provider is.
  #
  # Deliberately has no commit/apply of its own anymore (Mark, 2026-08-08:
  # "we're seeing records coming in as additional metadata from an
  # enrichment source and they should follow the same process no matter
  # whether they're a Goodreads source from the RSS or an ISFDB source" —
  # a field plan on its own used to be committable in isolation, which is
  # exactly what let a Goodreads cover conflict and an ISFDB cover
  # conflict end up in two differently-shaped PendingDecision kinds for
  # no principled reason, just because of which code path happened to
  # process it). Every plan this produces — regardless of source — flows
  # through Enrichment::SourceRecorder.integrate, which is the one place
  # that decides fill vs. bundle vs. hold, and the one place that commits
  # anything.
  module FieldApplier
    Plan = Struct.new(:record, :field, :action, :value, :source, :current, keyword_init: true)

    def self.plan(record, field, value, source)
      return Plan.new(action: :skipped) if value.blank?

      current = record.public_send(field)
      return Plan.new(record: record, field: field, action: :fill, value: value, source: source) if current.blank?
      return Plan.new(action: :unchanged) if normalize(current) == normalize(value)

      Plan.new(record: record, field: field, action: :conflict, value: value, source: source, current: current)
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

module Enrichment
  # Applies a manually-picked mix of field values across an edition's known
  # sources — the reconcile-edition screen's submit, and the quick
  # right-click cover-swap modal (a single "<provider>:cover_image" pick to
  # the same endpoint). Each pick names which EnrichmentRecord to take one
  # field's value from. No FieldApplier conflict gate: the reviewer is
  # choosing directly in front of the full comparison, the same trust
  # EditionReconciliationResolver and IsfdbEditionEnricher#commit_choice
  # already extend to a direct human pick.
  class EditionMetadataResolver
    class InvalidPick < StandardError; end

    def self.apply(edition, picks:) = new(edition).apply(picks)

    def initialize(edition)
      @edition = edition
    end

    # Returns the list of fields actually applied (for the flash message).
    def apply(picks)
      Array(picks).reject(&:blank?).map { |pick| apply_one(pick) }
    end

    private

    def apply_one(pick)
      provider, field = pick.to_s.split(":", 2)
      raise InvalidPick, "malformed pick #{pick.inspect}" if provider.blank? || field.blank?

      record = EnrichmentRecord.latest(entity: @edition, provider: provider)
      raise InvalidPick, "no #{provider} record on file for this edition" unless record

      field == "cover_image" ? apply_cover(record) : apply_field(record, field)
      field
    end

    def apply_field(record, field)
      raise InvalidPick, "#{record.provider} has no #{field} on file" unless record.fields.key?(field)

      @edition.update!(field => record.fields[field], field_sources: @edition.field_sources.merge(field => record.provider))
    end

    def apply_cover(record)
      raise InvalidPick, "#{record.provider} has no cover on file" unless record.cover_image.attached?

      @edition.cover_image.attach(record.cover_image.blob)
      @edition.update!(field_sources: @edition.field_sources.merge("cover_image" => record.provider))
    end
  end
end

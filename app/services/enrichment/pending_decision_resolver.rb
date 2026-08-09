module Enrichment
  # Applies (accept) or discards (reject) a PendingDecision — the first
  # real code path for the "manual edit"/human-review half of
  # DATA_MODEL.md's EnrichmentRecord policy (Enrichment::SourceRecorder
  # only ever *creates* these; nothing resolved them until now).
  #
  # Two families of kind understand what accept means:
  # - enrichment_conflict: apply the selected proposed field values (all
  #   of them, by default — see `selected_fields`) onto the Edition
  #   entity, via PendingDecision#field_diffs (the same display-shaped
  #   view the review-queue UI renders from — a bundle of several fields
  #   and a single field both arrive here identically shaped, since
  #   they're the same mechanism now — see SourceRecorder.integrate).
  #   cover_image is a field_diffs entry too, but can't go through a
  #   plain record.update! (it's an Active Storage attachment, not a
  #   column), so it gets its own branch — reusing the blob already
  #   sitting on the source's own EnrichmentRecord (see
  #   EnrichmentRecord#attach_cover_from_url), no staging slot needed.
  # - reread_conflict: opens a new Reading for the confirmed reread,
  #   dated from the currently-reading event that raised it — see
  #   Goodreads::ShelfSync#currently_reading/#flag_pending.
  #
  # A kind with no known automatic action has an empty field_diffs and no
  # dispatch branch, so accept/reject then only changes
  # PendingDecision#status, never mutating an entity it doesn't
  # understand.
  class PendingDecisionResolver
    def self.accept(pending_decision, selected_fields: nil) = new(pending_decision).accept(selected_fields)
    def self.reject(pending_decision) = new(pending_decision).reject

    def initialize(pending_decision)
      @pending_decision = pending_decision
    end

    def accept(selected_fields = nil)
      case @pending_decision.kind
      when "reread_conflict" then accept_reread_conflict
      else accept_enrichment(selected_fields)
      end
      @pending_decision.update!(status: "accepted", resolved_at: Time.current, payload: @pending_decision.payload)
    end

    def reject
      @pending_decision.update!(status: "rejected", resolved_at: Time.current)
    end

    private

    # Accept = "yes, this is a genuine new reread" — open a new Reading.
    # The existing completed Reading is untouched (still the historical
    # record of the first read). Reject (handled generically above —
    # #entity is nil for this kind, so purge_own_candidate_cover is a
    # no-op) = "no, this was a Goodreads mixup" — do nothing, matching
    # ShelfSync#currently_reading's own framing of the ambiguity.
    def accept_reread_conflict
      work = Work.find_by(id: @pending_decision.payload["work_id"])
      edition = Edition.find_by(id: @pending_decision.payload["edition_id"])
      return unless work && edition

      Reading.create!(work: work, edition: edition, status: "reading", date_started: @pending_decision.payload["date_started"])
    end

    def accept_enrichment(selected_fields)
      record = @pending_decision.entity
      return unless record

      original_diffs = @pending_decision.field_diffs.select { |d| d[:proposed].present? || d[:field] == "cover_image" }
      diffs = selected_fields ? original_diffs.select { |d| selected_fields.map(&:to_s).include?(d[:field]) } : original_diffs
      cover_diff, field_diffs = diffs.partition { |d| d[:field] == "cover_image" }

      apply_fields(record, field_diffs) if field_diffs.any?
      apply_cover(record) if cover_diff.any?
      prune_payload(diffs) if selected_fields
    end

    def apply_fields(record, field_diffs)
      attributes = field_diffs.to_h { |d| [ d[:field], d[:proposed] ] }
      sources = field_diffs.to_h { |d| [ d[:field].to_s, d[:source] ] }
      record.update!(attributes.merge(field_sources: record.field_sources.merge(sources)))
    end

    # The proposing source's own copy of the cover already lives durably
    # on its EnrichmentRecord (see EnrichmentRecord#attach_cover_from_url)
    # — no staging slot needed, just reuse that blob directly.
    def apply_cover(record)
      source_record = EnrichmentRecord.latest(entity: record, provider: @pending_decision.payload["source"])
      return unless source_record&.cover_image&.attached?

      record.cover_image.attach(source_record.cover_image.blob)
      record.update!(field_sources: record.field_sources.merge("cover_image" => @pending_decision.payload["source"]))
    end

    # Keeps only the field names actually applied — payload["fields"] is
    # now a plain array of strings (Enrichment::FieldApplier.find_or_create_conflict),
    # so this is a plain array intersection rather than filtering an array
    # of hashes by a "field" key.
    def prune_payload(applied_diffs)
      return unless @pending_decision.payload["fields"]

      applied_field_names = applied_diffs.map { |d| d[:field] }
      @pending_decision.payload["fields"] &= applied_field_names
    end
  end
end

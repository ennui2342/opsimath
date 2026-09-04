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
    def self.accept(pending_decision, selected_fields: nil, pub_id: nil) = new(pending_decision).accept(selected_fields, pub_id:)
    def self.reject(pending_decision) = new(pending_decision).reject

    def initialize(pending_decision)
      @pending_decision = pending_decision
    end

    def accept(selected_fields = nil, pub_id: nil)
      case @pending_decision.kind
      when "reread_conflict" then accept_reread_conflict
      when "enrichment_printing_choice" then accept_printing_choice(selected_fields, pub_id)
      else accept_enrichment(selected_fields)
      end
      @pending_decision.update!(status: "accepted", resolved_at: Time.current, payload: @pending_decision.payload)
    end

    def reject
      @pending_decision.candidate_covers.purge_later if @pending_decision.candidate_covers.attached?
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

    # Accept = "this ISFDB printing (pub_id) is the one I own — apply the
    # fields I checked." No conflict gate: the reviewer picked both the
    # printing and the values in front of the full comparison. `pub_id`
    # comes from the radio in the chosen card's header.
    def accept_printing_choice(selected_fields, pub_id)
      record = @pending_decision.entity
      return unless record

      candidate = (@pending_decision.payload["candidates"] || []).find { |c| c["_isfdb_pub_id"].to_s == pub_id.to_s }
      raise ArgumentError, "no ISFDB candidate #{pub_id.inspect} in decision #{@pending_decision.id}" unless candidate

      # 2026-09-04 fix: this default (used only when no explicit selection
      # comes in — the real browser form always submits one checkbox per
      # field actually shown, so this only matters for a programmatic
      # accept like isfdb:resolve_duplicate_printings) was missing
      # cover_artist, silently dropping it whenever a caller didn't pass
      # fields itself.
      fields = selected_fields.presence || PendingDecision::EDITION_FIELD_ORDER + %w[cover_image]
      Enrichment::IsfdbEditionEnricher.commit_choice(
        record, candidate, fields: fields, cover_blob: @pending_decision.candidate_cover(pub_id)&.blob
      )
      @pending_decision.candidate_covers.purge_later if @pending_decision.candidate_covers.attached?
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

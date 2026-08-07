module Enrichment
  # Applies (accept) or discards (reject) a PendingDecision — the first
  # real code path for the "manual edit"/human-review half of
  # DATA_MODEL.md's EnrichmentRecord policy (Enrichment::FieldApplier
  # only ever *creates* these; nothing resolved them until now).
  #
  # Two families of kind understand what accept means:
  # - enrichment_field_conflict / enrichment_edition_mismatch: apply the
  #   selected proposed field values (all of them, by default — see
  #   `selected_fields`) onto the Edition entity, via
  #   PendingDecision#field_diffs (the same display-shaped view the
  #   review-queue UI renders from — a bundled mismatch's several fields
  #   and an isolated conflict's one both arrive here identically
  #   shaped). cover_image is a field_diffs entry too, but can't go
  #   through a plain record.update! (it's an Active Storage attachment,
  #   not a column), so it gets its own branch.
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
      purge_own_candidate_cover
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
      original_diffs = @pending_decision.field_diffs.select { |d| d[:proposed].present? || d[:field] == "cover_image" }
      diffs = selected_fields ? original_diffs.select { |d| selected_fields.map(&:to_s).include?(d[:field]) } : original_diffs
      cover_diff, field_diffs = diffs.partition { |d| d[:field] == "cover_image" }
      had_cover = original_diffs.any? { |d| d[:field] == "cover_image" }

      if record
        apply_fields(record, field_diffs) if field_diffs.any?
        apply_cover(record) if cover_diff.any?
        prune_payload(diffs) if selected_fields
      end

      record.candidate_cover_image.purge if record && had_cover && cover_diff.empty? && record.candidate_cover_image.attached?
    end

    def apply_fields(record, field_diffs)
      attributes = field_diffs.to_h { |d| [ d[:field], d[:proposed] ] }
      sources = field_diffs.to_h { |d| [ d[:field].to_s, d[:source] ] }
      record.update!(attributes.merge(field_sources: record.field_sources.merge(sources)))
    end

    # .detach, not .purge — cover_image and candidate_cover_image now
    # reference the same blob row. .purge on a shared blob only happens
    # to be safe today because Blob#purge rescues the FK-constraint
    # error it triggers; .detach is the operation that's actually
    # correct for "this slot is done, but the file is still in use."
    def apply_cover(record)
      record.cover_image.attach(record.candidate_cover_image.blob)
      record.candidate_cover_image.detach
      record.update!(field_sources: record.field_sources.merge("cover_image" => "isfdb"))
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

    # Only ever purges a candidate this exact decision staged — an
    # Edition can have a second, unrelated, still-pending decision (e.g.
    # an isolated enrichment_field_conflict alongside a bundled
    # enrichment_edition_mismatch carrying the cover); rejecting one must
    # never touch the other's staged candidate.
    def purge_own_candidate_cover
      entity = @pending_decision.entity
      return unless entity&.candidate_cover_image&.attached?
      return unless @pending_decision.field_diffs.any? { |d| d[:field] == "cover_image" }

      entity.candidate_cover_image.purge
    end
  end
end

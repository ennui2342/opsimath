# Keeps the review queue honest (docs/CATALOG.md, "Pending decisions stay
# live"): a pending decision about an edition is closed once there's
# nothing left to decide —
#
# - its edition is gone                                 -> rejected
# - an enrichment_conflict whose source record is gone  -> rejected
#   (e.g. "Not this printing?" replaced that provider's record)
# - an enrichment_conflict whose every field now agrees -> accepted
#   (publisher variants by the authority file; covers by checksum) —
#   the same close a fresh fetch makes (SourceRecorder.resolve_stale_conflict)
#
# Run after every interface change to an edition (`for_edition`), on an
# edition's destroy, and nightly over the whole queue (`all`), so a future
# feature that changes editions and forgets can't leave cruft behind.
module PendingDecisionSweep
  KINDS = %w[enrichment_conflict enrichment_printing_choice].freeze

  def self.for_edition(edition_id)
    settle(scope.where("payload->>'entity_id' = ?", edition_id.to_s))
  end

  # -> { "accepted" => n, "rejected" => n }
  def self.all = settle(scope)

  def self.scope = PendingDecision.pending.where(kind: KINDS).where("payload->>'entity_type' = 'Edition'")

  def self.settle(decisions)
    decisions.to_a.each_with_object(Hash.new(0)) do |decision, counts|
      status = verdict(decision) or next
      decision.candidate_covers.purge_later if decision.candidate_covers.attached?
      decision.update!(status:, resolved_at: Time.current)
      counts[status] += 1
    end
  end

  # nil while there's still something to decide.
  def self.verdict(decision)
    edition = Edition.find_by(id: decision.payload["entity_id"])
    return "rejected" unless edition
    return unless decision.kind == "enrichment_conflict"

    record = EnrichmentRecord.latest(entity: edition, provider: decision.payload["source"])
    return "rejected" unless record

    "accepted" if Array(decision.payload["fields"]).all? { |field| agrees?(edition, record, field) }
  end

  def self.agrees?(edition, record, field)
    if field == "cover_image"
      edition.cover_image.attached? && record.cover_image.attached? && edition.cover_image.blob.checksum == record.cover_image.blob.checksum
    else
      current, proposed = edition.public_send(field), record.fields[field]
      current.to_s.strip == proposed.to_s.strip ||
        (field == "publisher" && proposed.present? && Authority.resolve("publisher", proposed) == current)
    end
  end
end

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

  # Display-shaped view of the same two payload shapes
  # Enrichment::PendingDecisionResolver applies — one hash per disputed
  # field, regardless of whether this is an isolated
  # enrichment_field_conflict (one) or a bundled
  # enrichment_edition_mismatch (several). [] for a kind whose payload
  # doesn't carry field-level data at all (e.g. reread_conflict).
  def field_diffs
    if payload["fields"]
      payload["fields"].map do |f|
        { field: f["field"], current: f["current_value"], proposed: f["proposed"], source: payload["source"] }
      end
    elsif payload["field"]
      proposed = Array(payload["proposed"]).first
      [ { field: payload["field"], current: payload["current_value"], proposed: proposed&.dig("value"), source: proposed&.dig("source") } ]
    else
      []
    end
  end
end

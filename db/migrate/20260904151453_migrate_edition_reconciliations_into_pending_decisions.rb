# Folds EditionReconciliation into PendingDecision (kind:
# "edition_reconciliation") — Mark, 2026-09-04: "this is just another
# type of pending decision with a different type," having originally
# asked for it kept separate (docs/DATA_MODEL.md's own note on that
# original call). See PendingDecision#edition_reconciliation_cards,
# Goodreads::EditionReconciliationResolver.
#
# Each row becomes a PendingDecision with entity_type/entity_id pointing
# at the same Work (the model's existing generic #entity lookup — no new
# polymorphic column needed), resolution/resolved_edition_id folded into
# payload (no dedicated columns for those either — same jsonb payload
# every other kind already writes its own outcome data into), and status
# mapped from EditionReconciliation's own pending/resolved (resolution
# "rejected" maps to PendingDecision's "rejected", anything else
# resolved maps to "accepted" — there's no third status once the
# structural choice, whatever it was, has actually been carried out).
class MigrateEditionReconciliationsIntoPendingDecisions < ActiveRecord::Migration[8.1]
  class MigrationEditionReconciliation < ApplicationRecord
    self.table_name = "edition_reconciliations"
  end

  class MigrationPendingDecision < ApplicationRecord
    self.table_name = "pending_decisions"
  end

  def up
    MigrationEditionReconciliation.reset_column_information
    MigrationEditionReconciliation.find_each do |rec|
      feed_item = rec.payload["feed_item"] || {}
      payload = rec.payload.merge(
        "entity_type" => "Work", "entity_id" => rec.work_id,
        "title" => feed_item["title"], "author_name" => feed_item["author_name"]
      )
      payload["resolution"] = rec.resolution if rec.resolution
      payload["resolved_edition_id"] = rec.resolved_edition_id if rec.resolved_edition_id

      status =
        if rec.status == "resolved"
          rec.resolution == "rejected" ? "rejected" : "accepted"
        else
          "pending"
        end

      MigrationPendingDecision.create!(
        kind: "edition_reconciliation", payload: payload, status: status, run_id: rec.run_id,
        resolved_at: rec.resolved_at, created_at: rec.created_at, updated_at: rec.updated_at
      )
    end

    drop_table :edition_reconciliations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

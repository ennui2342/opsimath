# Deleting a copy that was a mistake (the book page; "What became of it"
# is for a copy that really left). Readings of it stay, no longer tied to
# a copy. If it was its edition's last copy and nothing else uses that
# edition — no readings of it, not part of another book — the edition goes
# too, so no empty card is left; queued decisions about it close as moot.
# paper_trail keeps the copy and edition for reconstruction.
class CopyDeletion
  # -> true when the edition went with it
  def self.run(copy, work:)
    edition = copy.edition
    Copy.transaction do
      Reading.where(copy:).update_all(copy_id: nil)
      copy.destroy!
      next false if edition.copies.exists? || edition.readings.exists? || edition.works.where.not(id: work.id).exists?

      PendingDecision.pending.where("payload->>'entity_type' = 'Edition' AND payload->>'entity_id' = ?", edition.id.to_s)
                     .find_each { |d| d.update!(status: "rejected", resolved_at: Time.current) }
      edition.destroy!
      true
    end
  end
end

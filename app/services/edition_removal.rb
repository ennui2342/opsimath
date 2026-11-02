# Removing an edition from a book (the "Which edition is this?" page) — a
# duplicate, or one added by mistake. Its copies and readings move to
# another edition of the book (`move_to:`), or go with it (`move_to:
# nil`); reviews belong to the book and stay either way. Queued decisions
# about it are closed as moot. Refused for a book's only edition, and for
# an edition another book shares (an omnibus), which would vanish from
# that book too. Edition, Copy and Reading keep paper_trail versions, so a
# removal can be reconstructed.
class EditionRemoval
  class Refused < StandardError; end

  def self.run(edition, work:, move_to: nil)
    raise Refused, "This is the book's only edition." if work.editions.where.not(id: edition.id).none?
    raise Refused, "Another book shares this edition." if edition.works.where.not(id: work.id).exists?
    raise Refused, "That's not another edition of this book." if move_to && (move_to == edition || !work.editions.include?(move_to))

    Edition.transaction do
      decisions(edition).each { |d| d.update!(status: "rejected", resolved_at: Time.current) }
      if move_to
        edition.copies.each { |c| c.update!(edition: move_to) }
        edition.readings.each { |r| r.update!(edition: move_to) }
      else
        edition.readings.each(&:destroy!)
        edition.copies.reload.each(&:destroy!)
      end
      edition.reload.destroy!
    end
  end

  def self.decisions(edition)
    PendingDecision.pending.where("payload->>'entity_type' = 'Edition' AND payload->>'entity_id' = ?", edition.id.to_s)
  end
end

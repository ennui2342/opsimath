# Removing a book from the catalogue entirely — a duplicate ("Books of
# Blood Volume 1" beside "…Volume One") or one added by mistake (the book
# page; getting rid of a book Mark owned is its editions' status, not
# this). Its editions go with it, except one another book shares (an
# omnibus), which only loses its link to this book. Its readings and
# reviews move to another book (`move_to:`, the duplicate kept) — readings
# onto that book's first edition — or, without one, readings are deleted
# and a book with reviews is refused: a review is never lost by accident.
# Queued decisions about the book or its editions close as moot. Work,
# Edition, Copy, Reading and Review keep paper_trail versions.
class WorkRemoval
  class Refused < StandardError; end

  def self.run(work, move_to: nil)
    raise Refused, "That's this book." if move_to == work
    raise Refused, "Move its reviews to another book first — they're not deleted with it." if move_to.nil? && work.reviews.any?
    raise Refused, "#{move_to.title} has no edition to move the readings onto." if move_to && work.readings.any? && move_to.editions.none?

    title = work.title
    Work.transaction do
      move_or_delete_readings(work, move_to)
      work.reviews.each { |r| r.update!(work: move_to) } if move_to
      work.editions.to_a.each { |edition| remove_edition(edition, work) }
      decisions(work).each { |d| d.update!(status: "rejected", resolved_at: Time.current) }
      # The legacy wishlist's rows (no model any more, but its foreign key remains).
      Work.connection.delete(Work.sanitize_sql([ "DELETE FROM wishlist_items WHERE work_id = ?", work.id ])) if Work.connection.table_exists?(:wishlist_items)
      work.reload.destroy!
      CatalogueEvent.record(kind: "work_deleted", work: move_to,
                            summary: "Removed “#{title}” from the catalogue#{" (its readings and reviews moved to “#{move_to.title}”)" if move_to}")
    end
  end

  def self.move_or_delete_readings(work, move_to)
    if move_to
      target = move_to.editions_in_order.first
      work.readings.each { |r| r.update!(work: move_to, edition: target, copy: EditionHolding.copy(target)) }
    else
      work.readings.each(&:destroy!)
    end
  end

  def self.remove_edition(edition, work)
    if edition.works.where.not(id: work.id).exists?
      EditionContent.where(edition:, work:).destroy_all
    else
      EditionRemoval.decisions(edition).each { |d| d.update!(status: "rejected", resolved_at: Time.current) }
      edition.copies.each(&:destroy!)
      edition.reload.destroy!
    end
  end

  def self.decisions(work)
    PendingDecision.pending.where("payload->>'entity_type' = 'Work' AND payload->>'entity_id' = ?", work.id.to_s)
  end

  # Books the readings and reviews could go to: the same author's others.
  def self.candidates(work)
    Work.joins(:work_contributors).where(work_contributors: { contributor_id: work.work_contributors.select(:contributor_id) })
        .where.not(id: work.id).distinct.order(:title)
  end
end

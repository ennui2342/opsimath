# "Not this edition" (docs/CATALOG.md, build step 7): an edition on file
# is the wrong printing, and Mark picks the right one from the same cards
# as adding a book. The edition *becomes* the chosen printing wholesale —
# the identity call a printing choice already makes
# (IsfdbEditionEnricher#commit_choice): a pick-and-mix of one printing's
# cover with another's date describes no real book. So every
# bibliographic field, the cover, the ISBN and provider identifiers and
# the provider records are cleared and the card fills the edition as if
# new. Its copies, readings and Goodreads provenance stay — they're
# about Mark's book, not which printing it was thought to be.
#
# Queued decisions about the old printing are settled: a printing choice
# is answered (accepted), and ISFDB / Open Library field conflicts are
# moot — they compared a different printing's record (rejected).
class EditionChange
  PROVIDERS = %w[isfdb openlibrary].freeze
  IDENTIFIERS = %w[isbn13 isbn10] + PROVIDERS

  def self.run(edition, card)
    Edition.transaction do
      settle_decisions(edition) # first: re-filling would close a stale conflict as "accepted"
      edition.update!(PendingDecision::EDITION_FIELD_ORDER.index_with(nil)
                        .merge("field_sources" => edition.field_sources.except(*PendingDecision::EDITION_FIELD_ORDER, "cover_image")))
      edition.cover_image.detach # not purge: the blob can be shared with a provider record
      edition.edition_identifiers.where(id_type: IDENTIFIERS).destroy_all
      edition.enrichment_records.where(provider: PROVIDERS).destroy_all
      AddBook::Create.fill(edition.reload, card).tap { PendingDecisionSweep.for_edition(edition.id) }
    end
  end

  # The pending decisions about this edition's printing.
  def self.decisions(edition)
    PendingDecision.pending.where(kind: %w[enrichment_printing_choice enrichment_conflict])
                   .where("payload @> ?", { entity_type: "Edition", entity_id: edition.id }.to_json)
                   .select { |d| d.kind == "enrichment_printing_choice" || PROVIDERS.include?(d.payload["source"]) }
  end

  def self.settle_decisions(edition)
    decisions(edition).each do |d|
      d.update!(status: d.kind == "enrichment_printing_choice" ? "accepted" : "rejected", resolved_at: Time.current)
      d.candidate_covers.purge_later
    end
  end
end

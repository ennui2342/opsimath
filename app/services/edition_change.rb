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

  # Then the cascade, at once (Isfdb::WorkLinks via BookAddedJob): the
  # work's ISFDB title becomes the new printing's, and its form, year,
  # language, title and series follow — Mark's way of cleaning the
  # catalogue is setting each edition to its right printing.
  def self.run(edition, card)
    was = CatalogueEvent.edition_label(edition)
    filled = Edition.transaction do
      settle_decisions(edition) # first: re-filling would close a stale conflict as "accepted"
      edition.update!(PendingDecision::EDITION_FIELD_ORDER.index_with(nil)
                        .merge("field_sources" => edition.field_sources.except(*PendingDecision::EDITION_FIELD_ORDER, "cover_image")))
      edition.cover_image.detach # not purge: the blob can be shared with a provider record
      edition.edition_identifiers.where(id_type: IDENTIFIERS).destroy_all
      edition.enrichment_records.where(provider: PROVIDERS).destroy_all
      AddBook::Create.fill(edition.reload, card).tap do |filled|
        PendingDecisionSweep.for_edition(edition.id)
        work = filled.works.first
        CatalogueEvent.record(kind: "printing_changed", work:,
                              summary: "#{CatalogueEvent.title(work)}: now the #{CatalogueEvent.edition_label(filled)} printing (was #{was})")
      end
    end
    filled.works.each do |work|
      remember_printings(work, card)
      BookAddedJob.perform_later(work.id)
    end
    filled
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

  # The chosen card's printings stored with the work, each with its own
  # title record (provider_work_id), so the cascade can relink the work to
  # it even when the printing came from a search, not the work's known
  # printings (Isfdb::WorkLinks).
  def self.remember_printings(work, card)
    Array(card).each do |raw|
      e = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : raw
      next unless PROVIDERS.include?(e["provider"]) && e["id"].present?

      row = ProviderEdition.find_or_initialize_by(work:, provider: e["provider"], provider_id: e["id"].to_s)
      row.update!(e.slice(*%w[isbn13 isbn10 title publisher binding publish_date language page_count cover_url cover_artist])
                   .merge("provider_work_id" => e["work_id"].presence&.to_s || row.provider_work_id))
    end
  end
end

# What an edition is to Mark — the book page's "Owned ▾" (docs/CATALOG.md).
# The interface talks only about editions; a Copy is the table behind
# this: whether he has, had or never had the printing, and when / where /
# for how much he got it. One per edition in practice (every one of the
# 2,055 at 2026-11-02), so this reads and writes the edition's first copy.
#
# STATUSES: a copy's disposition, plus "not_mine" — a printing read from a
# library or borrowed, never owned — which is an edition with no copy.
module EditionHolding
  STATUSES = Copy::DISPOSITION_LABELS.merge("not_mine" => "Not mine").freeze
  DETAILS = %i[acquired_date acquired_price acquired_source condition notes].freeze

  def self.status(edition) = edition.copies.min_by(&:id)&.disposition || "not_mine"

  def self.copy(edition) = edition.copies.min_by(&:id)

  def self.update(edition, status:, details: {})
    was = status(edition)
    status = status.presence_in(STATUSES.keys) || was
    Copy.transaction do
      if status == "not_mine"
        Reading.where(copy_id: edition.copies.select(:id)).update_all(copy_id: nil)
        edition.copies.destroy_all
      else
        (copy(edition) || edition.copies.build).update!(details.to_h.slice(*DETAILS).merge(disposition: status))
      end
    end
    work = edition.works.first
    label = "#{CatalogueEvent.title(work)} (#{CatalogueEvent.edition_label(edition)})"
    if was != status
      CatalogueEvent.record(kind: "status", work:, summary: "#{label}: #{STATUSES[was].downcase} → #{STATUSES[status].downcase}")
    elsif details.to_h.compact_blank.any?
      CatalogueEvent.record(kind: "details", work:, summary: "#{label}: purchase details updated")
    end
  end
end

class EditionIdentifier < ApplicationRecord
  belongs_to :edition

  validates :id_type, presence: true
  validates :value, presence: true

  EXTERNAL_URL_BY_TYPE = {
    "isfdb" => ->(value) { "https://www.isfdb.org/cgi-bin/pl.cgi?#{value}" },
    "goodreads" => ->(value) { "https://www.goodreads.com/book/show/#{value}" }
  }.freeze

  # The identifier types opsimath actually records, with display labels and
  # a canonical order — shared by every "list an edition's ids" surface
  # (Ui::EditionCardComponent on the web, the pocket app, PendingDecision's
  # comparison cards) so they don't each pick their own labels/order.
  TYPE_LABELS = { "isbn13" => "ISBN-13", "isbn10" => "ISBN-10", "isfdb" => "ISFDB", "goodreads" => "Goodreads" }.freeze
  DISPLAY_ORDER = TYPE_LABELS.keys.freeze

  def label = TYPE_LABELS.fetch(id_type, id_type.upcase)

  # A stable, meaningful id order for display: ISBNs first, then linkable
  # ids, then anything unrecognised. Takes an already-loaded collection
  # (the edition's `edition_identifiers`) and returns a sorted Array.
  def self.for_display(identifiers)
    identifiers.sort_by { |i| DISPLAY_ORDER.index(i.id_type) || DISPLAY_ORDER.size }
  end

  # nil for id_types with no canonical single-book page to link to
  # (isbn13/isbn10 have no one right destination — Amazon/OpenLibrary/etc
  # would all be a guess about which the collector actually wants).
  def external_url
    EXTERNAL_URL_BY_TYPE[id_type]&.call(value)
  end
end

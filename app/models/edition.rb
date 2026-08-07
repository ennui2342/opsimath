class Edition < ApplicationRecord
  has_paper_trail

  enum :format, {
    paperback: "paperback",
    hardcover: "hardcover",
    ebook: "ebook",
    audiobook: "audiobook",
    omnibus: "omnibus"
  }
  # publish_date is a plain EDTF-formatted string ("1978", "1978-06", or
  # "1978-06-15") rather than a `date` column — a `date` type can't
  # represent "only the year is known" without fabricating a day/month,
  # which is exactly the false-precision problem PHILOSOPHY.md warns
  # against. No separate precision column either: the string itself only
  # ever contains the digits actually known, so there's nothing else to
  # track. See docs/DATA_MODEL.md.
  PUBLISH_DATE_FORMAT = /\A\d{4}(-\d{2}(-\d{2})?)?\z/

  belongs_to :variant_of_edition, class_name: "Edition", optional: true
  has_many :variants, class_name: "Edition", foreign_key: :variant_of_edition_id, inverse_of: :variant_of_edition, dependent: :nullify

  has_one_attached :cover_image
  # A staged ISFDB-proposed cover awaiting review, when one already
  # exists — see Enrichment::IsfdbEditionEnricher#plan_cover. No
  # migration needed: Active Storage's join table is already polymorphic
  # on record_type/record_id/name, so a second named attachment slot
  # costs nothing.
  has_one_attached :candidate_cover_image

  has_many :edition_contents, dependent: :destroy
  has_many :works, through: :edition_contents
  has_many :edition_identifiers, dependent: :destroy
  has_many :edition_contributors, dependent: :destroy
  has_many :contributors, through: :edition_contributors
  has_many :copies, dependent: :destroy
  has_many :readings, dependent: :restrict_with_error
  has_many :enrichment_records, as: :entity, dependent: :destroy

  # No presence validation — Goodreads' RSS feed (Phase 2) gives no
  # binding/format signal at all for some editions; forcing a value would
  # fabricate data, same reasoning as publish_date's own EDTF fix. Left
  # blank until real ISFDB enrichment fills it in cleanly. The enum itself
  # still rejects any non-nil value outside the known set.
  validates :publish_date, format: { with: PUBLISH_DATE_FORMAT }, allow_nil: true
end

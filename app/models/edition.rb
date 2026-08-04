class Edition < ApplicationRecord
  has_paper_trail

  enum :format, {
    paperback: "paperback",
    hardcover: "hardcover",
    ebook: "ebook",
    audiobook: "audiobook",
    omnibus: "omnibus"
  }
  enum :publish_date_precision, { day: "day", month: "month", year: "year" }

  belongs_to :variant_of_edition, class_name: "Edition", optional: true
  has_many :variants, class_name: "Edition", foreign_key: :variant_of_edition_id, inverse_of: :variant_of_edition, dependent: :nullify

  has_one_attached :cover_image

  has_many :edition_contents, dependent: :destroy
  has_many :works, through: :edition_contents
  has_many :edition_identifiers, dependent: :destroy
  has_many :edition_contributors, dependent: :destroy
  has_many :contributors, through: :edition_contributors
  has_many :copies, dependent: :destroy
  has_many :readings, dependent: :restrict_with_error
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :format, presence: true
end

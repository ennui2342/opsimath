class EditionIdentifier < ApplicationRecord
  belongs_to :edition

  validates :id_type, presence: true
  validates :value, presence: true

  EXTERNAL_URL_BY_TYPE = {
    "isfdb" => ->(value) { "https://www.isfdb.org/cgi-bin/pl.cgi?#{value}" },
    "goodreads" => ->(value) { "https://www.goodreads.com/book/show/#{value}" }
  }.freeze

  # nil for id_types with no canonical single-book page to link to
  # (isbn13/isbn10 have no one right destination — Amazon/OpenLibrary/etc
  # would all be a guess about which the collector actually wants).
  def external_url
    EXTERNAL_URL_BY_TYPE[id_type]&.call(value)
  end
end

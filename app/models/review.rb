class Review < ApplicationRecord
  # Full history: reviews are written in opsimath now (docs/CATALOG.md).
  has_paper_trail

  enum :status, { draft: "draft", published: "published" }

  belongs_to :work
  belongs_to :reading, optional: true

  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
end

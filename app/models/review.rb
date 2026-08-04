class Review < ApplicationRecord
  has_paper_trail only: [ :text ]

  enum :status, { draft: "draft", published: "published" }

  belongs_to :work
  belongs_to :reading, optional: true

  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
end

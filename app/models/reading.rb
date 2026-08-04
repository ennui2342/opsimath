class Reading < ApplicationRecord
  has_paper_trail only: [ :private_notes ]

  enum :status, { reading: "reading", completed: "completed", dnf: "dnf", paused: "paused" }
  enum :source, { owned_copy: "owned_copy", library: "library", borrowed: "borrowed", other: "other" }

  belongs_to :work
  belongs_to :edition
  belongs_to :copy, optional: true

  has_many :reviews, dependent: :nullify

  validates :status, presence: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
end

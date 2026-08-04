class WorkAward < ApplicationRecord
  belongs_to :work
  belongs_to :award

  enum :status, { won: "won", nominated: "nominated" }

  validates :year, presence: true
end

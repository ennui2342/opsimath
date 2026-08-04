class PendingDecision < ApplicationRecord
  enum :status, { pending: "pending", accepted: "accepted", rejected: "rejected" }

  validates :kind, presence: true
end

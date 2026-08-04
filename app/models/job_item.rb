class JobItem < ApplicationRecord
  enum :status, { success: "success", failed: "failed", skipped: "skipped" }

  belongs_to :entity, polymorphic: true

  validates :run_id, presence: true
end

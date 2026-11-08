# Nightly, before the printing lookups: each collected line's numbers and
# each collected series' books Mark doesn't have become wants
# (LineWants::Sync, SeriesWants::Sync).
class LineWantsJob < ApplicationJob
  queue_as :default

  def perform(line_want_id = nil)
    return LineWants::Sync.run(LineWant.find(line_want_id)) if line_want_id

    LineWants::Sync.run_all + SeriesWants::Sync.run_all
  end
end

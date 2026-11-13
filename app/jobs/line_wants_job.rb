# Nightly, before the printing lookups: each collected line's numbers and
# each collected series' and list's books Mark doesn't have become wants
# (LineWants::Sync, SeriesWants::Sync, BookListWants::Sync) — award lists
# re-read from ISFDB first, so a new year's shortlist is in.
class LineWantsJob < ApplicationJob
  queue_as :default

  def perform(line_want_id = nil)
    return LineWants::Sync.run(LineWant.find(line_want_id)) if line_want_id

    BookList.find_each do |list|
      next BookLists::Import.new.curated(list.key) if list.kind == "curated" # unmatched entries tried again

      BookLists::Import.new.award(list.isfdb_award_category_id)
    rescue StandardError => e # ISFDB down: yesterday's entries stand
      Rails.logger.warn("award list #{list.name}: #{e.class}: #{e.message}")
    end
    LineWants::Sync.run_all + SeriesWants::Sync.run_all + BookListWants::Sync.run_all
  end
end

module ApplicationHelper
  SOURCE_LABELS = { "isfdb" => "ISFDB", "openlibrary" => "Open Library", "goodreads" => "Goodreads" }.freeze

  # One line for a queued decision on the book page: "ISFDB's record
  # differs on publisher, language, page count and cover."
  def decision_summary(decision)
    source = SOURCE_LABELS.fetch(decision.payload["source"].to_s, decision.payload["source"].to_s.humanize.presence || "A provider")
    fields = Array(decision.payload["fields"]).map { |f| f == "cover_image" ? "cover" : f.humanize(capitalize: false) }
    case decision.kind
    when "enrichment_conflict" then "#{source}'s record differs on #{fields.to_sentence.presence || 'some details'}."
    when "edition_reconciliation" then "#{source} lists a different edition of this book."
    else "A decision about this edition is waiting."
    end
  end

  # Where the review screen's actions go: the queue (optionally one kind),
  # or back to the book page it was opened from.
  def decision_params(kind_filter) = { kind: kind_filter, work_id: params[:work_id] }.compact

  # Marks every find card on one cover of one book, so "Not this cover"
  # can remove them all at once.
  def find_cover_class(want, cover_id) = "find-cover-#{want.id}-#{cover_id}"
end

# A review item raised by the Goodreads sync when a feed row matches a
# `Work` you already own but not a specific `Edition` (the title+author
# fallback in `Goodreads::Matcher` fired, or a `goodreads_book_id` that's
# new for a book already catalogued). Kept separate from `PendingDecision`
# by design: that queue asks "which field value is right", this one asks
# "how does this record map onto my editions and copies" — structural
# resolutions, not a value pick. See docs/DATA_MODEL.md +
# docs/INTEGRATIONS.md's edition-level reconciliation addendum.
#
# Resolved by Goodreads::EditionReconciliationResolver.
class EditionReconciliation < ApplicationRecord
  belongs_to :work
  belongs_to :resolved_edition, class_name: "Edition", optional: true

  enum :status, { pending: "pending", resolved: "resolved" }
  enum :resolution, {
    relink: "relink",             # same edition, Goodreads churned its id
    change_edition: "change_edition", # swapped my copy for another edition
    add_edition: "add_edition",    # an additional copy alongside what I have
    unowned_read: "unowned_read",  # a library / borrowed / subscription read
    rejected: "rejected"           # ignore this feed event
  }, prefix: true

  # The feed row that raised this, rebuilt as the struct the sync works
  # with — the resolver replays it once the edition is confident.
  def feed_item
    Goodreads::RssClient::FeedItem.new(**payload.fetch("feed_item").symbolize_keys)
  end

  def shelf = payload["shelf"]
  def incoming_goodreads_id = payload["goodreads_book_id"]
  def incoming_isbn = payload.dig("feed_item", "isbn").presence

  # The work's current editions — the "which one is this / or is it new"
  # choice the reviewer makes.
  def candidate_editions
    work.editions.order(:id)
  end
end

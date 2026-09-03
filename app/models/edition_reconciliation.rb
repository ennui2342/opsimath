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

  # The structural calls the reviewer picks between, as [value, label, hint]
  # — rendered as a radio group on the review screen. `rejected` is a
  # separate button (different weight), same as PendingDecision's Reject.
  RESOLUTION_CHOICES = [
    [ "relink",         "Relink",         "same book — Goodreads changed its edition id" ],
    [ "change_edition", "Change edition",  "you swapped your copy; the old one is kept as replaced" ],
    [ "add_edition",    "Add edition",     "you own this one alongside what you already had" ],
    [ "unowned_read",   "Unowned read",    "a library / borrowed / subscription read — no copy added" ]
  ].freeze

  # Field order for an edition card — mirrors PendingDecision::EDITION_FIELD_ORDER,
  # trimmed to what a Goodreads-sourced edition actually carries.
  CARD_FIELDS = %w[format format_detail publisher publish_date].freeze
  ID_LABELS = { "isbn13" => "ISBN-13", "isbn10" => "ISBN-10", "isfdb" => "ISFDB", "goodreads" => "Goodreads" }.freeze

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

  # Same shape PendingDecision#comparison_cards returns, for the same
  # Ui::ComparisonCardComponent: the incoming Goodreads row as the
  # `proposed` card, then one selectable card per owned edition.
  def comparison_cards
    { incoming: incoming_card, editions: candidate_editions.map { |e| edition_card(e) } }
  end

  private

  def incoming_card
    item = feed_item
    fields = [
      card_row("goodreads id", item.goodreads_book_id),
      card_row("isbn", item.isbn),
      card_row("read", item.user_read_at),
      card_row("rating", item.user_rating),
      card_row("review", ("yes" if item.user_review.present?))
    ].compact
    Ui::ComparisonCardComponent::Card.new(
      label: "Goodreads · incoming", proposed: true,
      cover_url: item.book_image_url.presence, fields: fields
    )
  end

  def edition_card(edition)
    fields = CARD_FIELDS.map do |f|
      value = edition.public_send(f)
      value = value&.humanize if f.start_with?("format")
      Ui::ComparisonCardComponent::FieldRow.new(name: f, value: value)
    end
    Ui::ComparisonCardComponent::Card.new(
      label: edition_card_label(edition),
      cover: edition.cover_image, show_empty_cover: true,
      fields: fields,
      identifiers: edition.edition_identifiers.map { |i| [ ID_LABELS.fetch(i.id_type, i.id_type.upcase), i.value ] },
      select_name: "target_edition_id", select_value: edition.id.to_s,
      selected: edition.id == candidate_editions.first&.id
    )
  end

  def edition_card_label(edition)
    marks = []
    marks << "owned" if edition.copies.any? { |c| c.disposition == "owned" }
    marks << "read" if edition.readings.any?
    "Edition · #{marks.presence&.join(" · ") || "catalog"}"
  end

  def card_row(name, value)
    return nil if value.blank?
    Ui::ComparisonCardComponent::FieldRow.new(name: name, value: value)
  end
end

# Keeps each edition up to date from the printing it's anchored to
# (docs/CATALOG.md, "Anchored editions", build step 3). An edition's anchor
# is its ISFDB publication, else its Open Library edition — an `isfdb` /
# `openlibrary` EditionIdentifier — or, for one with neither, the single
# known printing its ISBN identifies. The anchor's record is read from
# ProviderEdition (KnownEditionsRefresh keeps it current), so this makes no
# network calls.
#
# Per field, against the anchor:
#   :same            nothing to do
#   :fill            empty on the edition — take the anchor's value
#   :update          the value came from the anchor's provider, which now says otherwise
#   :replace         it came from another provider (Goodreads) or no recorded
#                    source, and the anchor says otherwise — the anchor wins
#   :manual          Mark's own value — never touched
#   :anchor_blank    the anchor has nothing — the edition's value stays
# Then, for fields still empty, other providers' records of the same
# printing (a unique shared ISBN) can fill them (:secondary_fill).
#
# Editions whose printing is in question — a pending printing choice, or a
# decision flagged "looks like a different printing" — are held: refreshing
# them from a wrong anchor would make things worse.
#
# `plan` is a dry run.
class AnchoredRefresh
  FieldPlan = Struct.new(:field, :action, :current, :proposed, :source, keyword_init: true)
  EditionPlan = Struct.new(:edition, :work, :anchor_status, :anchor, :fields, :secondary, keyword_init: true)
  # anchor_status: :anchored | :by_isbn (would be anchored now) | :held | :missing_record | :ambiguous | :unanchored

  FIELDS = %i[publisher publish_date page_count language cover_artist format format_detail].freeze
  ANCHOR_TYPES = %w[isfdb openlibrary].freeze

  def self.plan(editions = default_scope) = new.plan(editions)

  def self.default_scope
    Edition.includes(:edition_identifiers, { cover_image_attachment: :blob }, works: :provider_editions)
  end

  def plan(editions)
    held = held_edition_ids
    editions.find_each.map { |edition| plan_edition(edition, held) }
  end

  private

  def held_edition_ids
    PendingDecision.pending.where("payload->>'entity_type' = 'Edition'")
                   .where("kind = 'enrichment_printing_choice' OR payload ? 'identity_question'")
                   .pluck(Arel.sql("payload->>'entity_id'")).map(&:to_i).to_set
  end

  def plan_edition(edition, held)
    work = edition.works.first
    known = work ? work.provider_editions.to_a : []
    base = { edition:, work:, fields: [], secondary: [] }
    return EditionPlan.new(**base, anchor_status: :held) if held.include?(edition.id)

    status, anchor = find_anchor(edition, known)
    return EditionPlan.new(**base, anchor_status: status) unless anchor

    fields = compare(edition, anchor)
    EditionPlan.new(**base, anchor_status: status, anchor:, fields:, secondary: secondary_fills(edition, anchor, known, fields))
  end

  def find_anchor(edition, known)
    ids = edition.edition_identifiers.select { |i| ANCHOR_TYPES.include?(i.id_type) }
    ANCHOR_TYPES.each do |provider|
      id = ids.find { |i| i.id_type == provider }&.value or next
      row = known.find { |r| r.provider == provider && r.provider_id == id }
      return [ :anchored, row ] if row
      return [ :missing_record, nil ] if provider == "isfdb" # linked, but its record isn't on file yet
    end

    isbn = isbn_of(edition) or return [ :unanchored, nil ]
    ANCHOR_TYPES.each do |provider|
      matches = known.select { |r| r.provider == provider && r.isbn == isbn }
      return [ :by_isbn, matches.first ] if matches.one?
      return [ :ambiguous, nil ] if matches.size > 1 && provider == "isfdb"
    end
    [ :unanchored, nil ]
  end

  def isbn_of(edition)
    ids = edition.edition_identifiers
    ids.find { |i| i.id_type == "isbn13" }&.value || ids.find { |i| i.id_type == "isbn10" }&.value&.then { |v| Isbn.to_13(v) }
  end

  def proposals(row)
    AddBook::Create.fields(AddBook::EditionCards.from_provider_editions([ row ]).first)
  end

  def compare(edition, anchor)
    proposed = proposals(anchor)
    plans = FIELDS.map do |field|
      current, value = edition.public_send(field), proposed[field]
      source = edition.field_sources[field.to_s]
      action =
        if value.blank? then current.blank? ? :same : :anchor_blank
        elsif current.blank? then :fill
        elsif current.to_s.strip == value.to_s.strip then :same
        elsif source == "manual" then :manual
        elsif source == anchor.provider then :update
        else :replace
        end
      FieldPlan.new(field:, action:, current:, proposed: value, source:)
    end
    plans << cover_plan(edition, anchor, proposed[:cover_image])
  end

  # The cover: fill when there's none; an update when the anchor's cover
  # image has changed since it was taken (its URL differs from the one on
  # the provider's record of this edition).
  def cover_plan(edition, anchor, url)
    taken = EnrichmentRecord.where(entity: edition, provider: anchor.provider).pick(:raw_payload)&.then { |r| r["cover_url"].to_s.split("|").first }
    action =
      if url.blank? then :same
      elsif !edition.cover_image.attached? then :fill
      elsif edition.field_sources["cover_image"] == "manual" then :manual
      elsif taken.present? && taken != url then :update
      else :same
      end
    FieldPlan.new(field: :cover_image, action:, current: taken, proposed: url, source: edition.field_sources["cover_image"])
  end

  def secondary_fills(edition, anchor, known, plans)
    still_empty = FIELDS.select { |f| edition.public_send(f).blank? && plans.find { |p| p.field == f }&.proposed.blank? }
    return [] if still_empty.empty? || anchor.isbn.blank?

    others = known.select { |r| r.provider != anchor.provider && r.isbn == anchor.isbn }
    return [] unless others.one?

    values = proposals(others.first)
    still_empty.filter_map { |f| FieldPlan.new(field: f, action: :secondary_fill, proposed: values[f], source: others.first.provider) if values[f].present? }
  end
end

require "net/http"

module Goodreads
  # Per-shelf sync behavior for one Goodreads::RssClient::FeedItem — the
  # ongoing-sync counterpart to Phase 1's Importer. See
  # docs/INTEGRATIONS.md's Phase 2 addendum for the full design and the
  # real-data findings behind it.
  #
  # `sync(item, shelf, prior_payload)` is the one entry point Syncer calls.
  # `prior_payload` is the existing GoodreadsSyncState row's
  # `last_synced_payload` (an empty hash if this is the first time this
  # (goodreads_book_id, shelf) pair has been seen) — carries the
  # previously-touched `Reading` id forward so an edited rating/review on
  # an already-closed read doesn't create a duplicate Reading. Returns an
  # `Outcome` (`entity` — the touched record, for `JobItem`'s polymorphic
  # association; `payload` — the new state to persist in
  # `GoodreadsSyncState#last_synced_payload`; `edition`/`created` — so the
  # caller (`GoodreadsSyncJob`) can trigger ISFDB enrichment and
  # notifications for a genuinely new `Edition` without re-deriving it).
  class ShelfSync
    Outcome = Struct.new(:entity, :payload, :edition, :created, keyword_init: true)
    Cataloged = Struct.new(:work, :edition, :pending, :created, keyword_init: true)

    READ_LIKE_STATUS = { "read" => "completed", "did-not-finish" => "dnf" }.freeze

    def self.sync(item, shelf, prior_payload)
      new(item, prior_payload).sync(shelf)
    end

    def initialize(item, prior_payload)
      @item = item
      @prior_payload = prior_payload
    end

    def sync(shelf)
      case shelf
      when "wishlist" then wishlist
      when "to-read" then to_read
      when "currently-reading" then currently_reading
      when "read", "did-not-finish" then read_like(READ_LIKE_STATUS.fetch(shelf))
      else raise ArgumentError, "unknown shelf #{shelf}"
      end
    end

    private

    # Wishlist never touches Work/Edition/Copy — see docs/INTEGRATIONS.md's
    # explicit "only a WishlistItem" policy.
    def wishlist
      existing = WishlistItem.where("external_ids ->> 'goodreads' = ?", @item.goodreads_book_id).first
      return Outcome.new(entity: existing, payload: {}, created: false) if existing

      info = RowParser.series_info(@item.title)
      series = info.series_name && Series.where("lower(name) = ?", info.series_name.downcase).first
      wishlist_item = WishlistItem.create!(
        title: info.title,
        author_name: RowParser.clean_name(@item.author_name),
        series: series,
        external_ids: { "goodreads" => @item.goodreads_book_id }
      )
      Outcome.new(entity: wishlist_item, payload: {}, created: true)
    end

    def to_read
      cataloged = ensure_cataloged
      Outcome.new(entity: cataloged.edition || cataloged.pending, payload: {}, edition: cataloged.edition, created: cataloged.created)
    end

    # Real finding (Mark caught this): a book can enter the library for
    # the first time via currently-reading, not just to-read (a magazine
    # issue started the day it arrived, never shelved anywhere first) — so
    # this gets the same auto-create-if-unmatched behavior as to_read, not
    # just "open a Reading against an existing match".
    def currently_reading
      cataloged = ensure_cataloged
      work, edition = cataloged.work, cataloged.edition
      return Outcome.new(entity: cataloged.pending, payload: {}, created: false) unless work

      if work.readings.exists?(status: "reading")
        Outcome.new(entity: edition, payload: {}, edition: edition, created: cataloged.created) # already open — no-op, not a new event
      elsif work.readings.exists?(status: "completed")
        # Already read before, no open Reading, and currently-reading just
        # fired again — genuinely ambiguous (intentional reread vs a
        # forgotten-to-close mixup), don't guess. date_started carried in
        # `extra` so PendingDecisionResolver can open a real Reading if
        # this does turn out to be a genuine reread.
        pd = flag_pending("reread_conflict", work: work, edition: edition, extra: { "date_started" => @item.user_date_added })
        Outcome.new(entity: pd, payload: {}, edition: edition, created: cataloged.created)
      else
        reading = Reading.create!(work: work, edition: edition, status: "reading", date_started: @item.user_date_added)
        Outcome.new(entity: reading, payload: { "reading_id" => reading.id }, edition: edition, created: cataloged.created)
      end
    end

    def read_like(status)
      cataloged = ensure_cataloged
      work, edition = cataloged.work, cataloged.edition
      return Outcome.new(entity: cataloged.pending, payload: {}, created: false) unless work

      reading = Reading.find_by(id: @prior_payload["reading_id"]) ||
                work.readings.find_by(status: "reading") ||
                matching_completed_reading(work) ||
                Reading.new(work: work, edition: edition, status: status)
      reading.status = status
      reading.date_finished = @item.user_read_at
      reading.rating = @item.user_rating if @item.user_rating.present?
      reading.save!

      attach_review(reading) if @item.user_review.present?

      Outcome.new(entity: reading, payload: { "reading_id" => reading.id }, edition: edition, created: cataloged.created)
    end

    # Guards against the Phase-1/Phase-2 duplication bug: a completed/dnf
    # Reading with no tracked GoodreadsSyncState (created by Importer, or
    # any future non-ShelfSync write path) landing on the same (work,
    # date_finished) is the same real read event, not a new one. work_id
    # only, never edition_id — Matcher's tier-3 fallback can bind an
    # arbitrary edition of the work, not reliably comparable across two
    # separately-created Readings of the same book. Guarded on
    # user_read_at.present? so two genuinely dateless reads (Importer's
    # own deliberate "ordinary single-read, no dates" case) are never
    # silently collapsed into one.
    def matching_completed_reading(work)
      return nil if @item.user_read_at.blank?

      work.readings.where(status: %w[completed dnf]).find_by(date_finished: @item.user_read_at)
    end

    def attach_review(reading)
      return if reading.reviews.exists?

      Review.create!(
        work: reading.work, reading: reading, text: @item.user_review,
        rating: @item.user_rating, status: "published", channels: [ { "channel" => "goodreads" } ]
      )
    end

    # Auto-create policy (confirmed in docs/INTEGRATIONS.md): a minimal
    # Work/Edition/Copy from the feed's limited fields when nothing
    # matches, flagged for enrichment rather than blocked on a human.
    # Deletes the matching WishlistItem, if any — the real wishlist ->
    # catalog transition (see docs/INTEGRATIONS.md).
    def ensure_cataloged
      match = Matcher.match(@item)
      if match&.ambiguous
        pd = flag_pending("possible_duplicate_work", work: nil, edition: nil)
        return Cataloged.new(work: nil, edition: nil, pending: pd, created: false)
      end

      work, edition, created =
        if match
          [ match.work, match.edition, false ]
        else
          create_work_and_edition + [ true ]
        end

      delete_wishlist_item
      Cataloged.new(work: work, edition: edition, pending: nil, created: created)
    end

    def delete_wishlist_item
      WishlistItem.where("external_ids ->> 'goodreads' = ?", @item.goodreads_book_id).destroy_all
    end

    def create_work_and_edition
      info = RowParser.series_info(@item.title)
      author = RowParser.clean_name(@item.author_name)

      work = Work.create!(
        title: info.title,
        literary_form: literary_form,
        original_publication_year: @item.book_published.presence&.to_i
      )
      link_series(work, info)
      link_contributor(work, author)
      link_shelves(work)
      ensure_fiction_subject(work)

      # format/publisher deliberately left blank — the RSS feed gives no
      # signal for either; ISFDB enrichment fills them in cleanly rather
      # than a fabricated guess (see the Phase 0 format fix). page_count
      # is technically available (book/num_pages) but left unused
      # regardless — Mark's own call (docs/INTEGRATIONS.md) is to treat
      # Goodreads' page count as unreliable no matter the source.
      # publish_date is deliberately left blank too: confirmed
      # empirically (a live RSS fetch cross-referenced against the CSV's
      # two distinct columns for the same books) that book_published is
      # the WORK's original publication year, not this specific
      # edition's — unlike the CSV export, which genuinely has both as
      # separate columns. Using it here would silently mislabel a
      # work-level fact as edition-specific, same false-precision shape
      # as the publish_date EDTF fix and the format fix before it.
      edition = ActiveRecord::Base.transaction do
        edition = Edition.create!
        EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: @item.goodreads_book_id)
        EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: @item.isbn) if @item.isbn.present?
        # fields: {} — audit parity with CSV import (a real
        # EnrichmentRecord(provider: "goodreads") row exists for every
        # auto-created edition, not just CSV-imported ones), even though
        # the RSS feed has no field data worth applying here.
        Enrichment::SourceRecorder.record(entity: edition, provider: "goodreads", external_id: @item.goodreads_book_id, raw_payload: @item.to_h)
        edition
      end
      EditionContent.create!(edition: edition, work: work)
      Copy.create!(edition: edition, disposition: "owned")
      attach_cover(edition, @item.book_image_url)

      [ work, edition ]
    end

    # Same download-and-attach shape as
    # Enrichment::IsfdbEditionEnricher#plan_cover's :fill path — no
    # existing cover to compare against yet on a just-created Edition, so
    # nothing to stage as a candidate, just a plain fill. Failure is
    # logged, not raised: a missing/unreachable cover shouldn't block
    # cataloging the rest of the item.
    def attach_cover(edition, url)
      return if url.blank?

      uri = URI.parse(url)
      return unless %w[http https].include?(uri.scheme)

      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      edition.cover_image.attach(
        io: StringIO.new(response.body),
        filename: File.basename(uri.path).presence || "cover.jpg",
        content_type: response.content_type || "image/jpeg"
      )
      # Recorded as "goodreads", not left untracked — so a later ISFDB
      # pass knows this cover is its own unreviewed automated fill, not
      # something to protect with a conflict check (see
      # IsfdbEditionEnricher::FILL_ELIGIBLE_COVER_SOURCES).
      edition.update!(field_sources: edition.field_sources.merge("cover_image" => "goodreads"))
    rescue StandardError => e
      Rails.logger.warn("goodreads cover download failed for edition #{edition.id}: #{e.message}")
    end

    def literary_form
      RowParser.literary_form_from_shelves(@item.user_shelves.join(",")) ||
        (RowParser.periodical_title?(@item.title) ? "periodical" : nil) ||
        "novel"
    end

    def link_series(work, info)
      return unless info.series_name

      series = Series.where("lower(name) = ?", info.series_name.downcase).first
      series ||= Series.create!(name: info.series_name)
      WorkSeries.find_or_create_by!(work: work, series: series) { |ws| ws.position = info.position }
    end

    def link_contributor(work, author)
      return unless author

      contributor = Contributor.find_or_create_by!(name: author)
      WorkContributor.find_or_create_by!(work: work, contributor: contributor, role: "author")
    end

    SKIPPED_SHELF_LABELS = (RowParser::LITERARY_FORM_SHELF_SIGNALS.keys + %w[fiction]).freeze

    def link_shelves(work)
      @item.user_shelves.each do |label|
        next if SKIPPED_SHELF_LABELS.include?(label.downcase)

        genre = Genre.find_by("lower(name) = ?", RowParser.genre_lookup_name(label).downcase)
        if genre
          WorkGenre.find_or_create_by!(work: work, genre: genre)
          next
        end

        subject = Subject.find_by("lower(name) = ?", RowParser.subject_lookup_name(label).downcase)
        if subject
          WorkSubject.find_or_create_by!(work: work, subject: subject)
          next
        end

        tag = Tag.find_or_create_by!(name: label)
        WorkTag.find_or_create_by!(work: work, tag: tag)
      end
    end

    FICTION_LITERARY_FORMS = %w[novel novella short_story collection anthology].freeze

    def ensure_fiction_subject(work)
      return unless FICTION_LITERARY_FORMS.include?(work.literary_form)
      return if work.subjects.any?

      fiction = Subject.find_by!(name: "Fiction")
      WorkSubject.find_or_create_by!(work: work, subject: fiction)
    end

    def flag_pending(kind, work:, edition:, extra: {})
      core = {
        "goodreads_book_id" => @item.goodreads_book_id, "title" => @item.title,
        "author_name" => @item.author_name, "work_id" => work&.id, "edition_id" => edition&.id
      }
      existing = PendingDecision.where(kind: kind, status: "pending").where("payload @> ?", core.to_json).first
      existing || PendingDecision.create!(kind: kind, payload: core.merge(extra))
    end
  end
end

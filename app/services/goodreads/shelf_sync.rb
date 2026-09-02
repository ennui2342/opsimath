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
    # `changed` — deliberately distinct from `created`: `created` means
    # "a brand-new Work/Edition was just catalogued"; `changed` means "a
    # real database write happened as a result of this specific touch,"
    # true for every `created: true` case but also true for e.g. a
    # genuinely new Reading against an *already*-catalogued edition.
    # Real bug found live in production (2026-08-08): a cold-start resync
    # (every GoodreadsSyncState wiped, so `Syncer` calls `ShelfSync` for
    # every item in every RSS page regardless of whether anything about
    # it is actually new) exposed that several branches below correctly
    # detected "already known, nothing to do" and made zero writes, but
    # the caller had no way to tell that apart from a genuine change —
    # so it notified "Added to wishlist"/"Started reading" for books
    # that had been on the wishlist/currently-reading for ages. `changed`
    # is exactly the signal `GoodreadsSyncJob` needs to only notify on
    # real changes, matching Mark's own framing: only what's actually
    # different since the CSV export should be acted on and reported.
    Outcome = Struct.new(:entity, :payload, :edition, :created, :changed, keyword_init: true)
    Cataloged = Struct.new(:work, :edition, :pending, :created, :wishlist_removed, keyword_init: true)

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
      return Outcome.new(entity: existing, payload: {}, created: false, changed: false) if existing

      info = RowParser.series_info(@item.title)
      series = info.series_name && Series.where("lower(name) = ?", info.series_name.downcase).first
      external_ids = { "goodreads" => @item.goodreads_book_id }
      external_ids["isbn10"] = @item.isbn if @item.isbn.present? # so a shop scan can match a not-yet-owned book (docs/MOBILE.md)
      wishlist_item = WishlistItem.create!(
        title: info.title,
        author_name: RowParser.clean_name(@item.author_name),
        series: series,
        cover_url: @item.book_image_url,
        external_ids: external_ids
      )
      Outcome.new(entity: wishlist_item, payload: {}, created: true, changed: true)
    end

    # changed: either a brand-new Edition was catalogued, or an existing
    # WishlistItem was actually removed (the real wishlist -> to-read
    # transition) — a plain re-match of an already-to-read book with
    # nothing left to remove is a genuine no-op.
    def to_read
      cataloged = ensure_cataloged
      Outcome.new(
        entity: cataloged.edition || cataloged.pending, payload: {}, edition: cataloged.edition,
        created: cataloged.created, changed: cataloged.created || cataloged.wishlist_removed
      )
    end

    # Real finding (Mark caught this): a book can enter the library for
    # the first time via currently-reading, not just to-read (a magazine
    # issue started the day it arrived, never shelved anywhere first) — so
    # this gets the same auto-create-if-unmatched behavior as to_read, not
    # just "open a Reading against an existing match".
    def currently_reading
      cataloged = ensure_cataloged
      work, edition = cataloged.work, cataloged.edition
      return Outcome.new(entity: cataloged.pending, payload: {}, created: false, changed: false) unless work

      if work.readings.exists?(status: "reading")
        # Already open — no-op, not a new event. Can only be reached when
        # cataloged.created is false (a just-created Work can't already
        # have an open Reading), so changed is always false here.
        Outcome.new(entity: edition, payload: {}, edition: edition, created: cataloged.created, changed: false)
      elsif work.readings.exists?(status: "completed")
        # Already read before, no open Reading, and currently-reading just
        # fired again — genuinely ambiguous (intentional reread vs a
        # forgotten-to-close mixup), don't guess. date_started carried in
        # `extra` so PendingDecisionResolver can open a real Reading if
        # this does turn out to be a genuine reread.
        pd = flag_pending("reread_conflict", work: work, edition: edition, extra: { "date_started" => @item.user_date_added })
        Outcome.new(entity: pd, payload: {}, edition: edition, created: cataloged.created, changed: cataloged.created)
      else
        reading = Reading.create!(work: work, edition: edition, status: "reading", date_started: @item.user_date_added)
        Outcome.new(entity: reading, payload: { "reading_id" => reading.id }, edition: edition, created: cataloged.created, changed: true)
      end
    end

    def read_like(status)
      cataloged = ensure_cataloged
      work, edition = cataloged.work, cataloged.edition
      return Outcome.new(entity: cataloged.pending, payload: {}, created: false, changed: false) unless work

      reading = Reading.find_by(id: @prior_payload["reading_id"]) ||
                work.readings.find_by(status: "reading") ||
                matching_completed_reading(work, edition) ||
                Reading.new(work: work, edition: edition, status: status)
      reading.status = status
      reading.date_finished = @item.user_read_at
      reading.rating = @item.user_rating if @item.user_rating.present?
      # Captured before save! — an existing Reading matched via
      # prior_payload/matching_completed_reading and re-set to the exact
      # same real values (the overwhelmingly common re-touch case on a
      # cold-start resync) makes no real change; reading.changed? only
      # answers that question pre-save, since save! clears dirty state.
      reading_changed = reading.new_record? || reading.changed?
      reading.save!

      review_added = @item.user_review.present? && attach_review(reading)

      Outcome.new(entity: reading, payload: { "reading_id" => reading.id }, edition: edition, created: cataloged.created, changed: reading_changed || review_added)
    end

    # Guards against the Phase-1/Phase-2 duplication bug: a completed/dnf
    # Reading with no tracked GoodreadsSyncState (created by Importer, or
    # any future non-ShelfSync write path) landing on the same (work,
    # date_finished) is the same real read event, not a new one. work_id
    # only, never edition_id — Matcher's tier-3 fallback can bind an
    # arbitrary edition of the work, not reliably comparable across two
    # separately-created Readings of the same book.
    #
    # A dateless RSS read event is handled separately, edition-scoped —
    # found live in production (2026-08-08): a cold-start resync (every
    # GoodreadsSyncState wiped) re-touched books whose CSV import had
    # created a dateless completed Reading (Importer's deliberate
    # "ordinary single-read, no dates" case — see docs/INTEGRATIONS.md).
    # Since the RSS item was *also* dateless for these, the date-based
    # match above never even runs, and every one landed as a genuine
    # duplicate Reading on the exact same edition. Two genuinely separate
    # dateless reads of the *same* edition, with nothing else to tell
    # them apart, are overwhelmingly more likely to be one real event
    # re-surfacing than two independent reads — so this branch collapses
    # them. Deliberately narrower than the dated branch: two dateless
    # reads of two *different* editions of the same work stay legitimately
    # ambiguous and uncollapsed, same reasoning the dated branch already
    # applies by staying work-scoped rather than edition-scoped.
    def matching_completed_reading(work, edition)
      return work.readings.where(status: %w[completed dnf]).find_by(date_finished: @item.user_read_at) if @item.user_read_at.present?

      work.readings.where(status: %w[completed dnf], edition: edition, date_finished: nil).first
    end

    def attach_review(reading)
      return false if reading.reviews.exists?

      Review.create!(
        work: reading.work, reading: reading, text: Reviews::Markdown.from_html(@item.user_review),
        rating: @item.user_rating, status: "published", channels: [ { "channel" => "goodreads" } ]
      )
      true
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
        return Cataloged.new(work: nil, edition: nil, pending: pd, created: false, wishlist_removed: false)
      end

      work, edition, created =
        if match
          record_goodreads_cover(match.edition) if match.edition
          [ match.work, match.edition, false ]
        else
          create_work_and_edition + [ true ]
        end

      wishlist_removed = delete_wishlist_item
      Cataloged.new(work: work, edition: edition, pending: nil, created: created, wishlist_removed: wishlist_removed)
    end

    # .any? — destroy_all returns the (possibly empty) array of destroyed
    # records, which is exactly the "did this touch actually change
    # anything" signal to_read/currently_reading need for a matched
    # (not newly-catalogued) book.
    def delete_wishlist_item
      WishlistItem.where("external_ids ->> 'goodreads' = ?", @item.goodreads_book_id).destroy_all.any?
    end

    # cover_image is the only field the RSS feed actually carries — a
    # matched (already-cataloged) edition is overwhelmingly a CSV import
    # row, whose goodreads EnrichmentRecord (if any) has no cover on it
    # yet (the CSV export carries no image URL column). Every sync touch
    # records what this fetch says onto that same per-(edition,
    # "goodreads") EnrichmentRecord — creating it on a genuinely new
    # edition, updating it in place otherwise (see
    # Enrichment::SourceRecorder.record) — and runs it through
    # SourceRecorder's own standard fill/conflict policy, the same one
    # ISFDB uses — a blank Edition.cover_image fills, a populated one
    # that genuinely differs raises a real conflict rather than being
    # silently dropped. Mark, 2026-08-08: deliberately no special-casing
    # for "this is Goodreads, so trust it less" — a populated destination
    # always goes to review, full stop, and no separate integration step
    # needed here beyond the one SourceRecorder.record already does.
    def record_goodreads_cover(edition)
      Enrichment::SourceRecorder.record(
        entity: edition, provider: "goodreads", external_id: @item.goodreads_book_id,
        raw_payload: @item.to_h, fields: { cover_image: @item.book_image_url }
      )
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
        # RSS only carries isbn10; derive isbn13 so a shop scan matches (docs/MOBILE.md).
        EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: @item.isbn) if @item.isbn.present?
        edition.backfill_isbn_pair!
        # No existing cover to compare against yet on a just-created
        # Edition, so this is always a plain fill in practice — but goes
        # through the same shared record_goodreads_cover path as a
        # matched edition anyway, for one policy in one place.
        record_goodreads_cover(edition)
        edition
      end
      EditionContent.create!(edition: edition, work: work)
      Copy.create!(edition: edition, disposition: "owned")

      [ work, edition ]
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

    # RSS <user_shelves> conflates the exclusive/status shelf
    # (currently-reading, to-read, read, ...) with the user's real custom
    # shelves — unlike the CSV export, whose "Bookshelves" column already
    # excludes it (RowParser.extra_shelves strips STATUS_SHELVES for the
    # Importer). Without STATUS_SHELVES here, a book auto-created while on
    # currently-reading/to-read gets a literal "currently-reading" Tag
    # that then shows as a lozenge on the work page forever.
    SKIPPED_SHELF_LABELS = (
      RowParser::LITERARY_FORM_SHELF_SIGNALS.keys + RowParser::STATUS_SHELVES + %w[fiction]
    ).freeze

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

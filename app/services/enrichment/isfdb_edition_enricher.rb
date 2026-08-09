module Enrichment
  # Enriches one Edition from isfdb-adapter's /isbn/{isbn} endpoint —
  # deliberately edition-scoped, not work-scoped: that endpoint returns
  # edition-shaped data (publisher, publish date, page count, cover),
  # and its "description"/"categories" fields are hardcoded empty in the
  # adapter's own current implementation (confirmed directly against its
  # source and the live mirror — title_synopsis is a dangling reference
  # to a table refresh.py doesn't import), so there's nothing to enrich
  # at the Work level yet. /search's fuzzy title/author matching is
  # deliberately out of scope for v1 too — a real, harder problem, not
  # rushed in alongside this.
  class IsfdbEditionEnricher
    Result = Struct.new(:status, :message, keyword_init: true)
    Plan = FieldApplier::Plan

    # Only the pub_ptype values confirmed live against the real mirror
    # (2026-08-05, via a read-only query through the running adapter pod)
    # that map confidently onto our format/format_detail. The long tail
    # (webzine, quarto, octavo, A4, "unknown", ...) is either not a
    # physical book format at all or a print-size term neither our
    # format enum nor ONIX format_detail has room for — left unmapped
    # rather than guessed, same discipline as the Goodreads importer's
    # own Binding mapping.
    FORMAT_BY_PTYPE = {
      "hc" => [ "hardcover", nil ],
      "tp" => [ "paperback", nil ], # US/UK trade ambiguous — same call as the Goodreads importer's "Trade Paperback"
      "pb" => [ "paperback", "mass_market" ],
      "digest" => [ "paperback", nil ],
      "pulp" => [ "paperback", nil ],
      "ebook" => [ "ebook", nil ],
      "audio cd" => [ "audiobook", nil ],
      "digital audio download" => [ "audiobook", nil ],
      "audio mp3 cd" => [ "audiobook", nil ]
    }.freeze

    def self.enrich(edition, client: Isfdb::Client.new)
      new(edition, client: client).enrich
    end

    # Re-applies an already-fetched payload (an existing EnrichmentRecord's
    # raw_payload) without hitting isfdb-adapter again — the concrete use
    # case DATA_MODEL.md's EnrichmentRecord section calls out for keeping
    # the full raw payload: "a source can be re-diffed later or fields
    # re-derived without re-fetching if mapping logic improves." Doesn't
    # create a new EnrichmentRecord (no new fetch happened) or re-resolve
    # the ISBN (the payload is already known to match this edition).
    def self.reprocess(edition, data)
      new(edition, client: nil).reprocess(data)
    end

    def initialize(edition, client:)
      @edition = edition
      @client = client
    end

    def enrich
      isbn = @edition.edition_identifiers.where(id_type: %w[isbn13 isbn10]).pick(:value)
      return Result.new(status: :skipped, message: "no isbn identifier") unless isbn

      data = @client.lookup_isbn(isbn)
      return Result.new(status: :skipped, message: "not found in isfdb mirror") unless data

      record_enrichment(data)
      reprocess(data)

      Result.new(status: :success)
    rescue Isfdb::ServiceError => e
      Result.new(status: :failed, message: e.message)
    end

    def reprocess(data)
      apply_fields(data)
      backfill_isfdb_identifier(data)
    end

    private

    # Independent of whatever apply_fields later decides to fill/conflict/
    # hold back — this is "what ISFDB's fetch literally said," captured
    # regardless of the eventual accept/reject outcome, so a standing
    # side-by-side comparison against another source's EnrichmentRecord is
    # always possible even with no active PendingDecision. Downloads and
    # attaches the proposed cover to this same record (see
    # EnrichmentRecord#attach_cover_from_url) so plan_cover below can
    # compare/stage against it without a second download.
    #
    # One EnrichmentRecord per (edition, "isfdb") — found and updated in
    # place on a re-enrich, not created fresh each time (same policy as
    # Enrichment::SourceRecorder.record; ISFDB stays a direct caller of
    # EnrichmentRecord here rather than going through SourceRecorder.record
    # itself since it needs the record back before apply_fields runs, and
    # its own per-field plans — not a generic fields hash — are what
    # actually get integrated).
    def record_enrichment(data)
      format, format_detail = FORMAT_BY_PTYPE[data["binding"].to_s.downcase]
      fields = {
        publisher: data["publisher"],
        language: data["language"],
        page_count: data["page_count"],
        publish_date: data["publish_date"],
        format: format,
        format_detail: format_detail,
        cover_image: data["cover_url"]
      }

      @enrichment_record = EnrichmentRecord.find_or_initialize_by(entity: @edition, provider: "isfdb")
      @enrichment_record.update!(
        external_id: data["_isfdb_pub_id"].to_s, fetched_at: Time.current, raw_payload: data,
        fields: @enrichment_record.fields.merge(fields.stringify_keys)
      )
      @enrichment_record.attach_cover_from_url(data["cover_url"])
      @enrichment_record
    end

    # Memoized so a plain `enrich` call (record_enrichment already ran
    # moments before) never re-queries — but reprocess can also be called
    # standalone via the class method, with no record_enrichment call in
    # this same instance's lifetime, so this falls back to the isfdb
    # EnrichmentRecord already on file for cases like that.
    def enrichment_record
      @enrichment_record ||= EnrichmentRecord.latest(entity: @edition, provider: "isfdb")
    end

    # Plans every candidate field before committing any of them. A blank
    # destination field isn't proof this fetch is safe to trust — the ISBN
    # could be describing a different specific printing entirely (isfdb-
    # adapter's own documented caveat: one ISBN can be reused across
    # distinct print runs), and that's exactly the kind of thing a human
    # looking at the full comparison (cover included) can judge for
    # themselves but this code can't. So the instant *any* field from this
    # fetch is a genuine :conflict, nothing from the fetch commits
    # silently — every field it proposed (fills and refinements too) goes
    # into one bundled review decision, offered piecemeal (checked by
    # default — accepting all of them reproduces today's auto-fill
    # outcome, but the reviewer can now see the whole record first and
    # uncheck anything that looks like it belongs to a different edition
    # instead of trusting it sight unseen). Mark, 2026-08-08.
    #
    # A lone :refine carries no such risk (it's the same fact restated
    # more precisely, not a disagreement), so with no real :conflict
    # present, fills and refinements alike still commit immediately, same
    # as before.
    def apply_fields(data)
      plans = [
        plan_publisher(data["publisher"]),
        FieldApplier.plan(@edition, :language, data["language"], "isfdb"),
        FieldApplier.plan(@edition, :page_count, data["page_count"], "isfdb"),
        plan_publish_date(data["publish_date"]),
        *plan_format(data["binding"]),
        plan_cover
      ]

      SourceRecorder.integrate(plans, entity: @edition, provider: "isfdb")
    end

    # Confirmed against real PendingDecision data: of 521 publisher
    # "conflicts" where one name is a substring of the other, 442 (85%)
    # are plain generic-suffix noise ("Tor Books" vs "Tor", "DAW" vs "DAW
    # Books") — genuinely the same publisher. The other 79 (15%) carry a
    # real territory qualifier ("Orbit" vs "Orbit (US)", "Roc" vs "Roc
    # UK") — but since this is an ISBN-keyed lookup, that qualifier
    # describes the exact printing the ISBN identifies, same as every
    # other field enrichment already trusts; it's not a competing guess
    # about the collector's copy. What actually determines whether a
    # substring match is safe is the multi-field check above, not
    # whether the extra text happens to look like a region — a
    # region-flavored refinement that co-occurs with another genuine
    # conflict gets held back (and bundled) exactly like any other.
    def plan_publisher(proposed)
      return Plan.new(action: :skipped) if proposed.blank?

      current = @edition.publisher
      return Plan.new(record: @edition, field: :publisher, action: :fill, value: proposed, source: "isfdb") if current.blank?
      return Plan.new(action: :unchanged) if normalize_name(current) == normalize_name(proposed)

      if substring_variant?(current, proposed)
        longer = [ current, proposed ].max_by(&:length)
        return Plan.new(action: :unchanged) if longer == current # already the more complete form

        return Plan.new(record: @edition, field: :publisher, action: :refine, value: longer, source: "isfdb")
      end

      Plan.new(record: @edition, field: :publisher, action: :conflict, value: proposed, source: "isfdb", current: current)
    end

    def substring_variant?(a, b)
      na, nb = normalize_name(a), normalize_name(b)
      na != nb && (na.include?(nb) || nb.include?(na))
    end

    def normalize_name(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    # publish_date is an EDTF string (see Edition::PUBLISH_DATE_FORMAT),
    # and isfdb-adapter's own date_str already normalizes ISFDB's raw
    # dates into the same shape ("1973-00-00" -> "1973", full dates pass
    # through). Because the string's own length *is* its precision, a
    # "conflict" here often isn't one: if the proposed value is current's
    # value with more digits appended (same year, or same year+month,
    # just more precise), that's a refinement.
    def plan_publish_date(raw)
      return Plan.new(action: :skipped) if raw.blank? || !raw.match?(Edition::PUBLISH_DATE_FORMAT)

      current = @edition.publish_date
      return Plan.new(record: @edition, field: :publish_date, action: :fill, value: raw, source: "isfdb") if current.blank?
      return Plan.new(action: :unchanged) if current == raw

      if raw.start_with?(current)
        Plan.new(record: @edition, field: :publish_date, action: :refine, value: raw, source: "isfdb")
      elsif current.start_with?(raw)
        Plan.new(action: :unchanged) # already at least as precise as isfdb's value
      else
        Plan.new(record: @edition, field: :publish_date, action: :conflict, value: raw, source: "isfdb", current: current)
      end
    end

    def plan_format(raw_ptype)
      format, format_detail = FORMAT_BY_PTYPE[raw_ptype.to_s.downcase]
      return [] unless format

      plans = [ FieldApplier.plan(@edition, :format, format, "isfdb") ]
      plans << FieldApplier.plan(@edition, :format_detail, format_detail, "isfdb") if format_detail
      plans
    end

    def backfill_isfdb_identifier(data)
      return if data["_isfdb_pub_id"].blank?

      EditionIdentifier.find_or_create_by!(edition: @edition, id_type: "isfdb", value: data["_isfdb_pub_id"].to_s)
    end

    # record_enrichment already downloaded the proposed cover onto its own
    # EnrichmentRecord (kept, not hotlinked or deferred to review time:
    # DATA_MODEL.md's Edition.cover_image note — an ISFDB cover URL can
    # and does go stale over time, and a PendingDecision can sit in the
    # queue for a while before a human reviews it), so there's nothing
    # left to stage here — accepting later just reuses that same blob
    # (see PendingDecisionResolver#apply_cover). The actual fill/conflict
    # decision is shared with every other cover-proposing source — see
    # CoverApplier.
    def plan_cover
      CoverApplier.plan(@edition, enrichment_record&.cover_image, "isfdb")
    end
  end
end

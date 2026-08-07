require "net/http"
require "digest"

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

    # field_sources["cover_image"] values that mean "not yet reviewed" —
    # nil (never touched) or "goodreads" (ShelfSync's own opportunistic
    # fill, itself unreviewed) — so a freshly-proposed ISFDB cover is a
    # plain fill rather than a conflict. Only a cover already backed by
    # "isfdb" (a prior confirmed ISFDB match) is worth protecting with a
    # comparison — see plan_cover.
    FILL_ELIGIBLE_COVER_SOURCES = [ nil, "goodreads" ].freeze

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

    def record_enrichment(data)
      EnrichmentRecord.create!(
        entity: @edition,
        provider: "isfdb",
        external_id: data["_isfdb_pub_id"].to_s,
        fetched_at: Time.current,
        raw_payload: data
      )
    end

    # Plans every candidate field before committing any of them — this is
    # what lets us tell "one field looks off" (a normal, isolated data
    # improvement or dispute) apart from "several fields disagree at
    # once" (isfdb-adapter's own documented caveat: one ISBN can be reused
    # across distinct print runs, so a multi-field disagreement is real
    # evidence the whole match describes a *different specific printing*,
    # not several independent facts to adjudicate one at a time).
    #
    # Plain fills never get held back regardless — they can't overwrite
    # or discard anything, whichever printing the data actually describes.
    # Only :refine/:conflict plans (the ones requiring an actual judgment
    # call) count toward that signal: with at most one, trust it as
    # before (apply an isolated refinement, or raise one normal
    # single-field PendingDecision for an isolated dispute); with two or
    # more, don't commit any of them individually — bundle the whole set
    # into one "review this edition" decision instead.
    def apply_fields(data)
      plans = [
        plan_publisher(data["publisher"]),
        FieldApplier.plan(@edition, :language, data["language"], "isfdb"),
        FieldApplier.plan(@edition, :page_count, data["page_count"], "isfdb"),
        plan_publish_date(data["publish_date"]),
        *plan_format(data["binding"]),
        plan_cover(data["cover_url"])
      ]

      plans.select { |p| p.action == :fill }.each { |p| commit_plan(p) }

      judgment_plans = plans.select { |p| %i[refine conflict].include?(p.action) }
      conflicts = judgment_plans.select { |p| p.action == :conflict }
      cover_conflict = judgment_plans.any? { |p| p.field == :cover_image && p.action == :conflict }

      # A genuine conflict alongside *anything* else needing judgment
      # (another conflict, or even an otherwise-safe refinement) is what
      # bundles — two independent refinements with no real disagreement
      # between them stay independent, since neither implies the other
      # might be wrong. A cover conflict always bundles on its own too,
      # even alone: "does this look like the right edition" (judged
      # primarily by the cover) is the common case this exists for, not
      # a corner case allowed to fall through to the isolated
      # enrichment_field_conflict path — which can't represent an
      # attachment in a JSON payload at all.
      if cover_conflict || (conflicts.any? && judgment_plans.size > 1)
        create_edition_mismatch(judgment_plans)
      else
        judgment_plans.each { |p| commit_plan(p) }
      end
    end

    def commit_plan(plan)
      plan.field == :cover_image ? commit_cover_plan(plan) : FieldApplier.commit(plan)
    end

    # :fill defers the actual attach to here, same as every other
    # field's fill path. :conflict already staged the candidate during
    # planning (see plan_cover) — a bundled conflict plan never reaches
    # commit_plan at all (bundled fields go straight to
    # create_edition_mismatch instead), so the candidate has to be
    # staged at plan time, not here.
    def commit_cover_plan(plan)
      return unless plan.action == :fill

      attach_bytes(@edition.cover_image, plan.value)
      @edition.update!(field_sources: @edition.field_sources.merge("cover_image" => "isfdb"))
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

    # The "review this edition" bundle — a different kind from
    # enrichment_field_conflict on purpose (per DATA_MODEL.md's
    # PendingDecision.kind being designed to extend without a new
    # mechanism): reviewing "does this ISBN match the right printing at
    # all" is a different question from "which value is correct for this
    # one field," and deserves its own single decision rather than
    # scattering across several field-level ones with no visible link
    # between them.
    # Find-or-create (not a plain create) so re-enriching an edition that
    # already has an unresolved mismatch doesn't silently overwrite a
    # staged candidate cover (has_one_attached — a second stage would
    # just replace the first) and spawn a second decision alongside it.
    def create_edition_mismatch(judgment_plans)
      fields = judgment_plans.map do |p|
        next { "field" => "cover_image" } if p.field == :cover_image

        { "field" => p.field.to_s, "current_value" => p.current, "proposed" => p.value }
      end

      existing = PendingDecision.where(kind: "enrichment_edition_mismatch", status: "pending")
                                 .where("payload @> ?", { entity_type: @edition.class.name, entity_id: @edition.id }.to_json)
                                 .first
      return existing if existing

      PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: {
          "entity_type" => @edition.class.name,
          "entity_id" => @edition.id,
          "source" => "isfdb",
          "fields" => fields
        }
      )
    end

    def backfill_isfdb_identifier(data)
      return if data["_isfdb_pub_id"].blank?

      EditionIdentifier.find_or_create_by!(edition: @edition, id_type: "isfdb", value: data["_isfdb_pub_id"].to_s)
    end

    # Downloads once, unconditionally — unlike the old attach_cover,
    # which returned before even reading cover_url once a cover already
    # existed, silently discarding whatever ISFDB proposed. The whole
    # point here is comparing against what's already attached, not just
    # filling a blank. Downloaded and kept, not hotlinked or deferred to
    # review time (DATA_MODEL.md's Edition.cover_image note — an ISFDB
    # cover URL can and does go stale over time, and a PendingDecision
    # can sit in the queue for a while before a human reviews it).
    # Failure here is logged, not raised: a missing cover shouldn't block
    # the fields above from being applied.
    def plan_cover(url)
      return Plan.new(action: :skipped) if url.blank?

      uri = URI.parse(url)
      return Plan.new(action: :skipped) unless %w[http https].include?(uri.scheme)

      downloaded = download_cover(uri)
      return Plan.new(action: :skipped) unless downloaded

      # Only an already ISFDB-confirmed cover is worth protecting with a
      # comparison. Anything else attached (nil field_sources — never
      # touched; or "goodreads" — ShelfSync's own opportunistic fill from
      # the RSS feed's book_image_url) is unreviewed and automated, same
      # as a genuinely blank cover: comparing two independently-sourced
      # cover PHOTOS byte-for-byte and treating a mismatch as a real
      # edition dispute doesn't work the way it does for text fields —
      # two different providers' scans of the same physical cover differ
      # trivially and near-universally, carrying no signal about whether
      # the ISBN match itself is right. Caught live: every freshly
      # RSS-auto-created edition with both a Goodreads cover and a
      # successful ISFDB match was spuriously flagged as a mismatch
      # before this fix, purely because the two photos didn't match
      # byte-for-byte.
      if !FILL_ELIGIBLE_COVER_SOURCES.include?(@edition.field_sources["cover_image"])
        if downloaded[:checksum] == @edition.cover_image.blob.checksum
          Plan.new(action: :unchanged)
        else
          attach_bytes(@edition.candidate_cover_image, downloaded)
          Plan.new(record: @edition, field: :cover_image, action: :conflict, source: "isfdb")
        end
      else
        Plan.new(record: @edition, field: :cover_image, action: :fill, value: downloaded, source: "isfdb")
      end
    rescue StandardError => e
      Rails.logger.warn("isfdb cover download failed for edition #{@edition.id}: #{e.message}")
      Plan.new(action: :skipped)
    end

    def download_cover(uri)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      {
        body: response.body, filename: File.basename(uri.path).presence || "cover.jpg",
        content_type: response.content_type || "image/jpeg", checksum: Digest::MD5.base64digest(response.body)
      }
    end

    def attach_bytes(attachment, downloaded)
      attachment.attach(io: StringIO.new(downloaded[:body]), filename: downloaded[:filename], content_type: downloaded[:content_type])
    end
  end
end

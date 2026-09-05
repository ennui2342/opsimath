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

    # Commit one specific ISFDB printing the reviewer picked in an
    # enrichment_printing_choice decision, applying only the fields they
    # checked. No FieldApplier / conflict gate — the human already made
    # the "which printing, which values" call in front of the full
    # comparison. `candidate_data` is a raw candidate hash straight out of
    # the decision's payload (an un-mutated lookup_isbn result).
    def self.commit_choice(edition, candidate_data, fields:, cover_blob: nil)
      new(edition, client: nil).commit_choice(candidate_data, fields, cover_blob)
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

    # Public wrapper around the private #resolve_candidate — the same
    # "confident pick" logic `enrich` uses on a fresh fetch, exposed for
    # `isfdb:resolve_duplicate_printings` to re-run against an already-
    # raised enrichment_printing_choice decision's stored candidates
    # (no new isfdb-adapter fetch needed; the candidates are already on
    # the decision's payload). Returns the winning raw candidate hash, or
    # nil if this is still a genuine "which one do I own" question.
    def self.resolve_candidate_for(edition, candidates)
      new(edition, client: nil).send(:resolve_candidate, candidates)
    end

    # Public wrapper around the private #same_edition? alone — doesn't
    # need an edition at all (the check is purely a function of the
    # candidate list, never `@edition`), so no edition argument here.
    # `isfdb:reconcile_printing_merges` uses this specifically rather
    # than #resolve_candidate_for: it needs to re-run *only* the
    # equivalence rule that was actually wrong, not the full cascade —
    # #resolve_candidate's earlier "matches the year already on file"
    # tier would read @edition.publish_date, which itself might already
    # be the bad merge's own mistaken write.
    def self.same_edition_for?(candidates)
      new(nil, client: nil).send(:same_edition?, candidates)
    end

    # Public wrapper around the private #attach_candidate_covers — also
    # edition-independent (it only touches the decision and the raw
    # candidate list). `isfdb:backfill_printing_choice_covers` uses this
    # to re-download covers for a decision that lost them: accepting a
    # printing choice purges `candidate_covers` (no longer needed once
    # resolved — see #flag_printing_choice's own comment), but reopening
    # a wrongly-accepted decision back to pending (`same_edition?`
    # correction, `isfdb:reconcile_printing_merges`) never re-fetches
    # them, since nothing about *that* operation implied a fresh fetch
    # was needed — a real gap found live 2026-09-05: a reopened decision
    # with real cover_url data on several candidates but zero attached.
    # Already-present covers aren't re-downloaded (mirrors
    # #attach_candidate_covers' own dedup-by-pub-id).
    def self.attach_candidate_covers_for(decision, candidates)
      new(nil, client: nil).send(:attach_candidate_covers, decision, candidates)
    end

    def initialize(edition, client:)
      @edition = edition
      @client = client
    end

    def enrich
      isbn = @edition.edition_identifiers.where(id_type: %w[isbn13 isbn10]).pick(:value)
      return Result.new(status: :skipped, message: "no isbn identifier") unless isbn

      candidates = @client.lookup_isbn(isbn)
      return Result.new(status: :skipped, message: "not found in isfdb mirror") if candidates.empty?

      data = resolve_candidate(candidates)
      unless data
        flag_printing_choice(candidates, isbn)
        return Result.new(status: :needs_review, message: "#{candidates.size} isfdb printings share isbn #{isbn}")
      end

      record_enrichment(data)
      reprocess(data)

      Result.new(status: :success)
    rescue Isfdb::ServiceError => e
      Result.new(status: :failed, message: e.message)
    end

    def reprocess(data)
      apply_fields(data)
      backfill_isfdb_identifier(data)
      backfill_isbn_identifiers(data)
    end

    def commit_choice(data, fields, cover_blob = nil)
      wanted = fields.map(&:to_s)
      @enrichment_record = record_enrichment(data) # provenance + a fresh cover blob

      attrs = candidate_fields(data).slice(*wanted)
      if attrs.any?
        @edition.update!(attrs.merge(field_sources: @edition.field_sources.merge(attrs.keys.index_with { "isfdb" })))
      end

      apply_choice_cover(cover_blob) if wanted.include?("cover_image")
      backfill_isfdb_identifier(data)
      backfill_isbn_identifiers(data)
    end

    private

    # The Edition-column values one ISFDB candidate proposes — the same
    # mapping record_enrichment captures, but returning only the ones fit
    # to write straight onto the Edition (blank/unmapped dropped).
    def candidate_fields(data)
      format, format_detail = FORMAT_BY_PTYPE[data["binding"].to_s.downcase]
      {
        "publisher" => data["publisher"].presence,
        "cover_artist" => cover_artist(data),
        "language" => data["language"].presence,
        "page_count" => data["page_count"],
        "publish_date" => (data["publish_date"] if data["publish_date"].to_s.match?(Edition::PUBLISH_DATE_FORMAT)),
        "format" => format,
        "format_detail" => format_detail
      }.compact
    end

    # Prefer the blob record_enrichment just downloaded (also now on the
    # isfdb EnrichmentRecord, for standing provenance); fall back to the
    # one already downloaded onto the PendingDecision at raise time if the
    # URL has since gone stale.
    def apply_choice_cover(fallback_blob = nil)
      blob = (@enrichment_record.cover_image.blob if @enrichment_record&.cover_image&.attached?) || fallback_blob
      return unless blob

      @edition.cover_image.attach(blob)
      @edition.update!(field_sources: @edition.field_sources.merge("cover_image" => "isfdb"))
    end

    # One PendingDecision listing every ISFDB printing that shares this
    # ISBN, for a human to pick the right one (radio) and choose which of
    # its fields to apply (checkboxes) — see PendingDecision#printing_choice_cards.
    # Raw candidates are stored verbatim so accept never re-hits the adapter;
    # each candidate's cover is downloaded now so the review screen shows
    # real images. Deduped on (edition) like create_bundled_decision.
    def flag_printing_choice(candidates, isbn)
      payload = {
        "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb",
        "isbn" => isbn, "candidates" => candidates
      }
      existing = PendingDecision.pending.where(kind: "enrichment_printing_choice")
                                .where("payload @> ?", { "entity_type" => "Edition", "entity_id" => @edition.id }.to_json)
                                .first
      decision = existing || PendingDecision.new(kind: "enrichment_printing_choice")
      decision.update!(payload: payload)
      attach_candidate_covers(decision, candidates)
      supersede_field_conflicts
      decision
    end

    # A printing choice's own review screen shows and lets the reviewer
    # pick *every* field an enrichment_conflict can be about (see
    # PendingDecision#printing_choice_cards). So the moment this decision
    # exists, a separate field-level conflict for the same Edition + isfdb
    # source is pure redundant queue noise — resolving the printing
    # choice settles those fields anyway. Mark, 2026-09-05, seeing both in
    # the queue for one book: "I assume the edition choice makes the
    # enrichment conflict moot, right?" — right, and it should never have
    # shown both. (accept_printing_choice has its own, stricter version
    # of this for a conflict raised *after* a printing choice already
    # existed — there it can only close one out if the accept genuinely
    # covered every disputed field.)
    def supersede_field_conflicts
      PendingDecision.pending.where(kind: "enrichment_conflict")
                     .where("payload @> ?", { "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb" }.to_json)
                     .find_each { |conflict| conflict.update!(status: "accepted", resolved_at: Time.current) }
    end

    def attach_candidate_covers(decision, candidates)
      have = decision.candidate_covers.map { |a| a.filename.base }
      candidates.each do |candidate|
        pub_id = candidate["_isfdb_pub_id"].to_s
        next if have.include?(pub_id)

        data = HasCoverImage.fetch_image(candidate["cover_url"])
        decision.candidate_covers.attach(**data.merge(filename: "#{pub_id}.jpg")) if data
      end
    end

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
        cover_artist: cover_artist(data),
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
        FieldApplier.plan(@edition, :cover_artist, cover_artist(data), "isfdb"),
        FieldApplier.plan(@edition, :language, data["language"], "isfdb"),
        FieldApplier.plan(@edition, :page_count, data["page_count"], "isfdb"),
        plan_publish_date(data["publish_date"]),
        *plan_format(data["binding"]),
        plan_cover
      ]

      SourceRecorder.integrate(plans, entity: @edition, provider: "isfdb")
    end

    # ISFDB credits cover art per-publication (COVERART title linked via
    # pub_content, its own canonical_author) — genuinely edition-level,
    # unlike everything else the adapter derives from the title. Goodreads
    # never proposes this field. Joined "First, Second" when more than one
    # artist is credited (real: dust-jacket art + photography, etc).
    def cover_artist(data)
      Array(data["cover_artists"]).join(", ").presence
    end

    # Confirmed against real PendingDecision data: of 521 publisher
    # "conflicts" where one name is a substring of the other, 442 (85%)
    # are plain generic-suffix noise ("Tor Books" vs "Tor", "DAW" vs "DAW
    # Books") — genuinely the same publisher. Another slice carries a
    # real territory qualifier ("Orbit" vs "Orbit (US)", "Roc" vs "Roc
    # UK") — but since this is an ISBN-keyed lookup, that qualifier
    # describes the exact printing the ISBN identifies, same as every
    # other field enrichment already trusts; it's not a competing guess
    # about the collector's copy.
    #
    # What's left is the case a bare substring test can't tell apart from
    # those: the extra word is a *distinct name*, not a formatting or
    # region difference — "Orbit" vs "Futura Orbit" (Futura's Orbit
    # imprint, later Little, Brown's), "Gollancz" vs "Victor Gollancz",
    # "Panther" vs "Panther Granada". One name containing the other is a
    # coincidence there; we can't assume the longer form is the right
    # one, so it goes to review like any other publisher conflict.
    #
    # For the merge-toward-completeness shortcut to fire, the extra text
    # the longer name carries has to be non-distinguishing:
    #   - the longer name is an imprint/parent form joined by "/" or "&"
    #     (joined_imprint_form?: "Gollancz / Orion"), OR
    #   - the only difference is a bracketed or comma-led qualifier tail
    #     ("Orbit" vs "Orbit (Hachette)", "Arrow Books" vs "Arrow Books
    #     (London)"), OR
    #   - every remaining extra token is a NON_DISTINGUISHING word —
    #     corporate form, format/imprint line, or territory.
    # Anything else ("Panther" vs "Panther Granada", "Gollancz" vs "Victor
    # Gollancz") is a genuine "which publisher is this" question and goes
    # to review.
    #
    # (A substring variant that co-occurs with another genuine conflict
    # is held back and bundled regardless — see SourceRecorder.integrate.)
    NON_DISTINGUISHING_PUBLISHER_WORDS = %w[
      books book press publishing publications publishers publ editions edition imprint
      ltd limited inc incorporated co company corp corporation plc pty gmbh group house
      paperbacks paperback hardback hardcover science fiction fantasy sf the and
      us usa uk gb can canada au aus australia nz london
    ].freeze

    def plan_publisher(proposed)
      return Plan.new(action: :skipped) if proposed.blank?

      current = @edition.publisher
      return Plan.new(record: @edition, field: :publisher, action: :fill, value: proposed, source: "isfdb") if current.blank?
      return Plan.new(action: :unchanged) if normalize_name(current) == normalize_name(proposed)

      if substring_variant?(current, proposed) && non_distinguishing_variant?(current, proposed)
        longer = [ current, proposed ].max_by(&:length)
        return Plan.new(action: :unchanged) if longer == current # already the more complete form

        return Plan.new(record: @edition, field: :publisher, action: :refine, value: longer, source: "isfdb")
      end

      Plan.new(record: @edition, field: :publisher, action: :conflict, value: proposed, source: "isfdb", current: current)
    end

    # Is the difference between two substring-related publisher names one
    # we can safely resolve by keeping the fuller form, rather than a
    # genuine "which publisher is this" question for a human?
    def non_distinguishing_variant?(a, b)
      return true if joined_imprint_form?([ a, b ].max_by(&:length))

      extra = core_name_tokens(a).to_set ^ core_name_tokens(b).to_set
      return true if extra.empty? && (qualifier_tail?(a) || qualifier_tail?(b)) # differ only by a (...) / ", ..." tail

      extra.any? && extra.all? { |word| NON_DISTINGUISHING_PUBLISHER_WORDS.include?(word) }
    end

    # "Gollancz / Orion", "Del Rey / Ballantine", "Hodder & Stoughton" —
    # ISFDB's house style for writing an imprint together with its parent
    # (or a co-publication). The "/" or "&" is the tell: not a competing
    # name for the same entity, the same entity written with its lineage
    # attached — and on an ISBN-keyed lookup that lineage describes the
    # exact printing, the same trust already extended to territory
    # qualifiers. Mark, 2026-09-02: trust the fuller form here.
    def joined_imprint_form?(name)
      name.to_s.match?(%r{[/&]})
    end

    # A trailing "(...)" group or everything after the first comma —
    # "(UK)", "(Hachette)", ", New York", ", Berkley Publishing Group".
    # On an ISBN-keyed lookup that's always a territory / city / parent
    # qualifier on this exact printing, never a competing identity, so it
    # doesn't block a merge and isn't compared token-by-token.
    def qualifier_tail?(name)
      name.to_s.match?(/\([^)]*\)\s*\z/) || name.to_s.include?(",")
    end

    def core_name_tokens(value)
      name_tokens(value.to_s.sub(/\s*\([^)]*\)\s*\z/, "").sub(/,.*\z/m, ""))
    end

    def name_tokens(value)
      value.to_s.downcase.split(/[^a-z0-9]+/).reject(&:blank?)
    end

    # An ISBN isn't always unique to one ISFDB publication — a real,
    # common case for reprinted vintage SF (confirmed 2026-08-10: 565 of
    # 1,493 of opsimath's own ISFDB-matched ISBNs hit this). isfdb-adapter
    # returns every candidate, most-recent-printing-first.
    #
    # Confident pick, tried in order: exactly one candidate; exactly one
    # whose publish year matches what's already on file (year-level, not
    # full EDTF precision — either side commonly knows only the year);
    # or — 2026-09-04, a real finding — every candidate actually
    # describing the *same* edition, just as separate ISFDB pub records
    # (a collaborative wiki: independent contributors re-entering a
    # printing they already had, one submission more complete than the
    # last). Confirmed against the real pending backlog: 74% of every
    # "which printing" decision raised had candidates agreeing on
    # publisher/binding/page count and differing only in how much of the
    # rest they'd filled in — not a genuine "which one do I own" question
    # at all. See #same_edition? for exactly what "the same" requires.
    # Anything else — no year on file (true for every RSS-auto-created
    # edition), the year matching none or several, and genuinely
    # different candidates — returns nil, and `enrich` raises an
    # enrichment_printing_choice decision rather than guessing which
    # printing the collector actually holds. Mark, 2026-09-03: don't
    # guess; show all the printings as cards.
    def resolve_candidate(candidates)
      return candidates.first if candidates.one?

      known_year = @edition.publish_date.presence&.slice(0, 4)
      if known_year
        matches = candidates.select { |c| c["publish_date"].to_s.start_with?(known_year) }
        return matches.first if matches.one?
      end

      richest_candidate(candidates) if same_edition?(candidates)
    end

    # 2026-09-05 audit (Mark: "this is sloppy... let's run through your
    # algorithm to make sure there's no mistakes" — first cut only
    # checked binding/publisher/page_count and wrongly merged 63 of 164
    # real accepted decisions, including collapsing back together the
    # exact Anubis Gates HarperCollins-UK-1993-vs-Triad-Grafton-1986 case
    # that motivated building enrichment_printing_choice in the first
    # place). Went through every field an isfdb-adapter candidate
    # actually carries, not just the two already caught, and checked each
    # one against the real accepted-decision backlog before deciding
    # whether it needed a rule:
    #
    # - `_isfdb_title_id` — ISFDB's own "same underlying novel" id, more
    #   fundamental than the title *string* (which legitimately varies —
    #   "Chapterhouse: Dune" / "Chapter House Dune" are the same book,
    #   different title records). A mismatch here means the ISBN matched
    #   genuinely distinct ISFDB entities, not just distinct printings of
    #   one — checked first, before anything else even matters.
    # - `binding` — exact (compared raw: an unmapped ptype maps to the
    #   same nil `FORMAT_BY_PTYPE` result as any other unmapped one,
    #   which would otherwise read as a false match).
    # - `publisher` — the existing non-distinguishing-variant
    #   normalization, applied pairwise.
    # - `cover_artists`, publish_date's *year*, `language` — exact
    #   agreement wherever any candidate actually states a value
    #   (#agrees_where_known?); a candidate that simply doesn't say never
    #   disagrees with one that does, same "blank isn't a disagreement"
    #   rule this file applies everywhere else. These three, especially
    #   cover_artists and year, are exactly what the real 63 turned out
    #   to hinge on — a genuinely re-illustrated reissue, or a real
    #   decade-plus reprint gap, reads as "different" now instead of
    #   silently merging.
    # - `page_count` — its own tolerance, `PAGE_COUNT_TOLERANCE`, since
    #   unlike the above it's genuinely ambiguous to count in the first
    #   place on a collaborative wiki (Mark, 2026-09-04): a small
    #   variance there is almost certainly a counting difference between
    #   contributors, not evidence of a separate printing, and it's the
    #   detail that matters least even on the rare occasion it does
    #   differ for real. Re-verified against the 101 decisions that
    #   *do* still merge under every check above: the actual page-count
    #   spread among them tops out at 5.0%, comfortably inside the 10%
    #   tolerance and nowhere near the ~7-19% range the real 63 needed
    #   the other checks to catch anyway.
    # - `authors`, `_isfdb_series_id` — checked too; in this backlog
    #   every case where either disagreed also disagreed on title_id or
    #   year, so they added no further cases, but they're real facts
    #   this app tracks and a future dataset might disagree on them
    #   without also tripping title_id or year — covered by the same
    #   #agrees_where_known? rule for the same reason.
    # - `title`, `subtitle`, `description`, `categories`, `cover_url`,
    #   `isbn_10`/`isbn_13`, `_isfdb_series_num` — not meaningful
    #   equivalence dimensions: constant per ISBN query, purely
    #   cosmetic/derived, or (title, cover_url) already superseded by a
    #   more authoritative field above.
    # `.size == 1`, deliberately not the bare `.uniq.one?` this used to
    # read — `Array#one?` with no block checks how many elements are
    # *truthy*, not the array's length. `_isfdb_title_id` is legitimately
    # nil for plenty of real ISFDB records, and `[nil].one?` is false (nil
    # isn't truthy) even though the array only has one distinct value —
    # a real bug found live 2026-09-05: two byte-for-byte identical
    # candidates, both with a nil title_id, wrongly failed this and
    # reopened a genuinely-correct merge. `binding` never actually hit
    # this (its `.to_s` guarantees a truthy string, even for nil), but
    # made explicit here too rather than leaving it correct by luck of
    # that side effect.
    def same_edition?(candidates)
      return false unless candidates.map { |c| c["binding"].to_s.downcase }.uniq.size == 1
      return false unless candidates.map { |c| c["_isfdb_title_id"] }.uniq.size == 1
      return false unless agrees_where_known?(candidates) { |c| c["authors"] }
      return false unless agrees_where_known?(candidates) { |c| c["_isfdb_series_id"] }
      return false unless agrees_where_known?(candidates) { |c| Array(c["cover_artists"]).sort.presence }
      return false unless agrees_where_known?(candidates) { |c| c["publish_date"].to_s[0, 4].presence }
      return false unless agrees_where_known?(candidates) { |c| c["language"].presence }

      candidates.map { |c| c["publisher"] }.combination(2).all? { |a, b| publisher_equivalent?(a, b) } &&
        page_counts_equivalent?(candidates)
    end

    # True when every candidate that actually states a value for
    # whatever the block extracts states the *same* one — a candidate
    # that leaves it blank never disagrees with one that doesn't. For the
    # exact-match dimensions only (#same_edition?'s callers); publisher
    # gets its own non-distinguishing-variant tolerance and page_count
    # its own percentage tolerance, both defined separately.
    def agrees_where_known?(candidates, &block)
      candidates.filter_map(&block).uniq.size <= 1
    end

    def publisher_equivalent?(a, b)
      return true if normalize_name(a) == normalize_name(b)

      substring_variant?(a, b) && non_distinguishing_variant?(a, b)
    end

    PAGE_COUNT_TOLERANCE = 0.1 # 10% of the larger count — see #same_edition?

    def page_counts_equivalent?(candidates)
      pages = candidates.filter_map { |c| c["page_count"] }.uniq
      return true if pages.size <= 1

      (pages.max - pages.min) <= pages.max * PAGE_COUNT_TOLERANCE
    end

    # Among equivalent candidates, prefer the one that actually says the
    # most — most precise publish_date (the string's own length is its
    # precision, same signal #plan_publish_date already trusts), then
    # whichever else has more of the fields this enricher cares about
    # filled in. Never the isfdb-adapter's own "most recent" default —
    # completeness, not recency, is what separates these once they're
    # already confirmed to be the same printing.
    def richest_candidate(candidates)
      candidates.max_by { |c| candidate_completeness(c) }
    end

    def candidate_completeness(c)
      [
        c["publish_date"].to_s.length,
        Array(c["cover_artists"]).any? ? 1 : 0,
        c["language"].present? ? 1 : 0,
        c["page_count"].present? ? 1 : 0
      ]
    end

    def substring_variant?(a, b)
      na, nb = normalize_name(a), normalize_name(b)
      na != nb && (na.include?(nb) || nb.include?(na))
    end

    # "&" and the word "and" are the same connector — "Faber & Faber" and
    # "Faber and Faber" are one publisher. Collapse both before stripping
    # punctuation, else the surviving "and" letters break the match
    # ("faberfaber" vs "faberandfaber").
    def normalize_name(value)
      value.to_s.downcase.gsub(/\s*&\s*|\s+and\s+/, " ").gsub(/[^a-z0-9]/, "")
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

    # ISFDB's pub record carries both ISBN forms. Fill whichever the
    # edition is missing — but only fill, never add a second value for a
    # type that's already present (that would be a real conflict, and the
    # ISBN is how this pub was matched in the first place, so it should
    # agree). Then derive anything still missing. See docs/MOBILE.md.
    def backfill_isbn_identifiers(data)
      { "isbn10" => Isbn.normalize(data["isbn_10"]), "isbn13" => Isbn.normalize(data["isbn_13"]) }.each do |id_type, value|
        next if value.blank? || @edition.edition_identifiers.exists?(id_type: id_type)

        @edition.edition_identifiers.create!(id_type: id_type, value: value)
      end
      @edition.backfill_isbn_pair!
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
    #
    # authoritative: true — by the time apply_fields/plan_cover runs, this
    # data is always for a specific, ISBN-confidently-resolved ISFDB pub
    # (enrich bails out entirely without an isbn identifier, and defers to
    # enrichment_printing_choice instead of calling this at all when more
    # than one pub shares that isbn — see #resolve_candidate). So a byte
    # difference here is never "which printing is this," only "ISFDB's
    # real cover for this exact printing differs from what's on file" —
    # safe to trust outright rather than routing through the visual-
    # compare-then-conflict gate CoverApplier otherwise applies. Mark,
    # 2026-09-04.
    def plan_cover
      CoverApplier.plan(@edition, enrichment_record&.cover_image, "isfdb", authoritative: true)
    end
  end
end

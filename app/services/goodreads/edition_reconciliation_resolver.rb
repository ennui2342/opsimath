module Goodreads
  # Applies a resolution to an edition_reconciliation PendingDecision —
  # see docs/DATA_MODEL.md and docs/INTEGRATIONS.md's edition-level
  # reconciliation addendum. Folded into PendingDecision 2026-09-04
  # (previously its own EditionReconciliation model/queue) — this
  # resolver stays its own class regardless, same as
  # Enrichment::IsfdbEditionEnricher#commit_choice being its own thing
  # PendingDecisionResolver delegates to: the resolution vocabulary here
  # (relink/change_edition/add_edition/unowned_read/rejected) has nothing
  # in common with accept/reject.
  #
  # relink / change_edition / add_edition make the goodreads_book_id
  # resolve to a confident Edition, then **replay** the original feed
  # event: `ShelfSync.sync` runs the normal shelf handling and opens the
  # deferred `Reading` / records the cover — one code path. The existing
  # `read_like` semantics then do the right thing: the feed's read date
  # matching a prior reading of the work re-touches it in place (no new
  # reading; a historical `Reading` never changes edition); a new date is
  # a new reading on the confident edition.
  #
  # unowned_read is handled directly — a library/borrowed read is its own
  # event on a catalog-only (no `Copy`) Edition, not something to route
  # through the owned-copy replay path.
  class EditionReconciliationResolver
    class InvalidResolution < StandardError; end

    UNOWNED_SOURCES = %w[library borrowed other].freeze
    READING_STATUS = { "read" => "completed", "did-not-finish" => "dnf", "currently-reading" => "reading" }.freeze

    def self.resolve(reconciliation, isfdb: Isfdb::Client.new, **kwargs)
      new(reconciliation, isfdb:).resolve(**kwargs)
    end

    def initialize(reconciliation, isfdb: Isfdb::Client.new)
      @rec = reconciliation
      @work = reconciliation.entity
      @item = reconciliation.feed_item
      @isfdb = isfdb
    end

    def resolve(resolution:, target_edition_id: nil, source: nil)
      case resolution.to_s
      when "relink"         then relink(target_edition_id); replay
      when "change_edition" then change_edition(target_edition_id); replay
      when "add_edition"    then @resolved_edition = build_owned; replay
      when "unowned_read"   then unowned_read(source)
      when "rejected"       then nil
      else raise InvalidResolution, "unknown resolution #{resolution.inspect}"
      end

      # No dedicated resolution/resolved_edition_id columns anymore —
      # PendingDecision only knows pending/accepted/rejected, so
      # "rejected" maps onto that status directly and everything else
      # (a genuine structural resolution, however it turned out) is
      # "accepted"; the specific resolution choice and which edition it
      # landed on are recorded into payload, same place every other kind
      # already stashes its own outcome data.
      status = resolution.to_s == "rejected" ? "rejected" : "accepted"
      @rec.update!(status: status, resolved_at: Time.current,
                   payload: @rec.payload.merge("resolution" => resolution.to_s, "resolved_edition_id" => @resolved_edition&.id))
      @rec
    end

    private

    def relink(edition_id)
      @resolved_edition = target(edition_id)
      EditionIdentifier.find_or_create_by!(edition: @resolved_edition, id_type: "goodreads", value: @rec.incoming_goodreads_id)
    end

    def change_edition(edition_id)
      old = target(edition_id)
      ActiveRecord::Base.transaction do
        old.copies.owned.update_all(disposition: "replaced")
        @resolved_edition = build_owned
      end
      enrich(@resolved_edition)
    end

    def unowned_read(source)
      raise InvalidResolution, "source must be one of #{UNOWNED_SOURCES.join('/')}" unless UNOWNED_SOURCES.include?(source.to_s)

      @resolved_edition = EditionBuilder.build(work: @work, item: @item) # no Copy — read, not owned
      enrich(@resolved_edition)

      status = READING_STATUS[@rec.shelf]
      return unless status # to-read / wishlist: catalog the edition, no reading

      Reading.create!(
        work: @work, edition: @resolved_edition, status: status, source: source,
        date_started: @item.user_date_added.presence,
        date_finished: (@item.user_read_at.presence if status != "reading"),
        rating: @item.user_rating.presence
      )
    end

    def build_owned
      edition = EditionBuilder.build(work: @work, item: @item)
      Copy.create!(edition: edition, disposition: "owned")
      edition
    end

    # Re-run the feed event now that Matcher resolves it confidently.
    def replay = ShelfSync.sync(@item, @rec.shelf, {})

    # ISFDB pass — outside any transaction (a network call, non-fatal on
    # failure, same as GoodreadsSyncJob#enrich_new_edition).
    def enrich(edition)
      Enrichment::IsfdbEditionEnricher.enrich(edition, client: @isfdb)
      edition
    end

    def target(edition_id)
      raise InvalidResolution, "target_edition_id required" if edition_id.blank?

      @work.editions.find(edition_id)
    end
  end
end

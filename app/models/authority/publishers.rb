module Authority
  # The "publisher" vocabulary handler — the catalogue-side behaviour that
  # sits behind Authority's generic model.
  #
  # apply(term):
  #   1. rewrite  — editions whose `publisher` is a *non-preferred* variant
  #      take the preferred form (decision: "establishing a term rewrites
  #      the catalogue").
  #   2. re-enrich — the *tight* set of editions the term actually affects
  #      (rewritten ones + the ones with a pending publisher conflict the
  #      term bridges) goes back through Enrichment::IsfdbEditionEnricher.
  #      reprocess. With the term in place the publisher no longer
  #      conflicts, so the fetch completes exactly as it would have if
  #      publisher had never been a problem: safe fills apply, the ISFDB
  #      cover applies authoritatively (Enrichment::CoverApplier's
  #      `authoritative:` policy), and the bundled decision either resolves
  #      or drops to just its genuinely-still-conflicting fields.
  #
  # retract(removed_labels:):
  #   1. restore  — each affected edition's publisher goes back to the
  #      value its original source's EnrichmentRecord recorded (Mark: "the
  #      data is always recoverable in the metadata records"), so the
  #      strings genuinely differ again.
  #   2. re-enrich — the same tight set, so the publisher conflict comes
  #      back where one genuinely exists.
  #
  # The re-enrich is scoped by `term_bridges?` — never the whole library,
  # never editions already on the preferred form with nothing pending.
  module Publishers
    VOCABULARY = "publisher"

    Result = Struct.new(:editions_rewritten, :editions_restored, :editions_reprocessed,
                        :conflicts_cleared, :conflicts_raised, keyword_init: true) do
      def self.blank = new(**members.index_with(0))
    end

    # What establishing a term *would* do, before it's done — so the
    # review screen and settings can show it. Mark, 2026-09-06, after
    # nearly making `Pan Books Ltd` a variant of `Tor / Pan Macmillan UK`
    # (would have blindly rewritten 6 old Pan paperbacks): a preview that
    # separates the rewrites ISFDB corroborates from the ones nothing
    # would catch.
    Preview = Struct.new(:preferred, :editions, keyword_init: true) do
      # editions: [{ id:, title:, publisher:, isfdb:, status: }]
      #   :corroborated — ISFDB names a publisher that resolves to this term
      #   :contradicted — ISFDB names a different publisher (rewrite raises a fresh conflict — recoverable)
      #   :unmatched    — no ISFDB record (blind rewrite, nothing catches a mistake)
      def rewritten = editions.size
      def corroborated = editions.count { |e| e[:status] == :corroborated }
      def contradicted = editions.count { |e| e[:status] == :contradicted }
      def unmatched = editions.count { |e| e[:status] == :unmatched }
      def risky? = contradicted.positive? || unmatched.positive?
    end

    class << self
      def label = "Publishers"

      def controlled_fields = %w[Edition#publisher]

      def usage(term)
        {
          editions: editions_on_variants(term, include_preferred: true).size,
          pending_conflicts: publisher_conflicts.count { |d| term_bridges?(d, term) }
        }
      end

      # Dry run — the editions `apply` would rewrite, each tagged by
      # whether ISFDB corroborates the rewrite. `variant_labels` may
      # include the preferred form itself (harmless — filtered).
      def preview(preferred:, variant_labels:)
        all_keys = ([ preferred ] + Array(variant_labels)).filter_map { |l| Authority.normalize(l).presence }.to_set
        rewrite_keys = all_keys - [ Authority.normalize(preferred) ]

        editions = editions_with_normalized_publisher(rewrite_keys).map do |e|
          isf = isfdb_publisher(e)
          work = e.works.first
          { id: e.id, work_id: work&.id, title: e.works.map(&:title).join(", ").presence || "Edition ##{e.id}",
            publisher: e.publisher, isfdb: isf, status: preview_status(isf, all_keys) }
        end
        order = %i[contradicted unmatched corroborated]
        Preview.new(preferred: preferred,
                    editions: editions.sort_by { |x| [ order.index(x[:status]), x[:title].downcase ] })
      end

      # :corroborated — ISFDB names a publisher that resolves to this term
      # :contradicted — ISFDB names a different publisher
      # :unmatched    — no ISFDB record to check against
      def preview_status(isfdb_name, term_keys)
        return :unmatched if isfdb_name.blank?

        term_keys.include?(Authority.normalize(isfdb_name)) ? :corroborated : :contradicted
      end

      def apply(term)
        to_rewrite = editions_on_variants(term)
        touched = to_rewrite.map(&:id) |
                  publisher_conflicts.select { |d| term_bridges?(d, term) }.map { |d| d.payload["entity_id"] }
        rewritten = rewrite(to_rewrite, term.preferred_label)

        result = run(touched)
        result.editions_rewritten = rewritten
        notify("Publisher term established", term, result)
        result
      end

      def retract(removed_labels:, preferred_label:)
        keys = removed_labels.map { |l| Authority.normalize(l) }.to_set
        restored = restore(editions_with_normalized_publisher(keys))

        # only editions the removed term genuinely affected: those on one
        # of its strings whose publisher now actually conflicts again
        # (not every edition that merely happens to sit on the preferred
        # form with nothing wrong)
        candidates = editions_with_normalized_publisher(keys) | restored
        touched = candidates.select { |e| genuinely_conflicts?(e) }.map(&:id)

        result = run(touched)
        result.editions_restored = restored.size
        notify("Publisher term retracted",
               Struct.new(:preferred_label, :variant_labels).new(preferred_label, removed_labels), result)
        result
      end

      private

      # Re-enrich `edition_ids`, reporting the before/after change in which
      # of them carry a pending publisher conflict.
      def run(edition_ids)
        edition_ids = edition_ids.uniq
        before = pending_publisher_conflict_ids & edition_ids
        n = reprocess(edition_ids)
        after = pending_publisher_conflict_ids & edition_ids

        Result.blank.tap do |r|
          r.editions_reprocessed = n
          r.conflicts_cleared = (before - after).size
          r.conflicts_raised = (after - before).size
        end
      end

      def reprocess(edition_ids)
        n = 0
        Edition.where(id: edition_ids).find_each do |edition|
          payload = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.raw_payload
          next if payload.blank?

          Enrichment::IsfdbEditionEnricher.reprocess(edition, payload)
          n += 1
        end
        n
      end

      # --- the term's reach --------------------------------------------------

      def editions_on_variants(term, include_preferred: false)
        keys = term.authority_variants.pluck(:normalized_label).to_set
        keys.delete(Authority.normalize(term.preferred_label)) unless include_preferred
        editions_with_normalized_publisher(keys)
      end

      def editions_with_normalized_publisher(keys)
        return [] if keys.empty?

        Edition.where.not(publisher: [ nil, "" ]).select { |e| keys.include?(Authority.normalize(e.publisher)) }
      end

      def publisher_conflicts
        PendingDecision.pending.where(kind: "enrichment_conflict")
                       .select { |d| (d.payload["fields"] || []).include?("publisher") }
      end

      def pending_publisher_conflict_ids
        publisher_conflicts.map { |d| d.payload["entity_id"] }
      end

      # Does this term bridge a *genuine* publisher disagreement on this
      # decision — the edition's value and the ISFDB value are different
      # strings that both resolve to the term? (Not "publisher happens to
      # be in the bundle but the two strings already matched", a stale
      # entry this term had nothing to do with.)
      def term_bridges?(decision, term)
        edition = Edition.find_by(id: decision.payload["entity_id"])
        proposed = isfdb_publisher(edition)
        return false if edition.nil? || proposed.blank?

        keys = term.authority_variants.pluck(:normalized_label).to_set
        current = Authority.normalize(edition.publisher)
        proposed = Authority.normalize(proposed)
        current != proposed && keys.include?(current) && keys.include?(proposed)
      end

      def isfdb_publisher(edition)
        EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.fields&.dig("publisher")
      end

      def genuinely_conflicts?(edition)
        proposed = isfdb_publisher(edition)
        proposed.present? &&
          Enrichment::IsfdbEditionEnricher.plan_publisher_for(edition, proposed).action == :conflict
      end

      # --- edits -----------------------------------------------------------

      # Returns the count actually changed.
      def rewrite(editions, preferred)
        editions.count { |e| e.publisher != preferred && e.update!(publisher: preferred) }
      end

      # Reset each edition's publisher to the value its original source's
      # EnrichmentRecord recorded, when that differs from what's on it now.
      def restore(editions)
        editions.filter_map do |e|
          provider = e.field_sources["publisher"].presence || "goodreads"
          original = EnrichmentRecord.latest(entity: e, provider: provider)&.fields&.dig("publisher")
          next if original.blank? || original == e.publisher

          e.update!(publisher: original)
          e
        end
      end

      def notify(title, term, result)
        Notifications.notify(Notifications::Event.new(
          kind: :authority_control, level: :info, title: title,
          fields: {
            "Vocabulary" => "publisher",
            "Preferred" => term.preferred_label,
            "Variants" => Array(term.variant_labels).join(", ").presence || "—",
            "Editions rewritten" => result.editions_rewritten,
            "Editions restored" => result.editions_restored,
            "Editions re-enriched" => result.editions_reprocessed,
            "Conflicts cleared" => result.conflicts_cleared,
            "Conflicts re-raised" => result.conflicts_raised
          }
        ))
      end
    end
  end
end

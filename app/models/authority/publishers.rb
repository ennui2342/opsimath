module Authority
  # The "publisher" vocabulary handler — the catalog-side behaviour that
  # sits behind Authority's generic model. Establishing or retracting a
  # publisher term has two consequences, both handled here:
  #
  #   1. rewrite  — editions whose `publisher` string is a variant of the
  #      term take the preferred form (decision: "establishing a term
  #      rewrites the catalog"). Retract never un-rewrites.
  #   2. re-enrich — the affected editions are put back through
  #      Enrichment::IsfdbEditionEnricher.reprocess (replays the stored
  #      ISFDB payload, no network). With the term in place a pending
  #      publisher conflict resolves itself; with it gone the conflict is
  #      raised again where one genuinely exists. Same mechanism both
  #      directions — no bespoke conflict-sweep or value-restore logic.
  #
  # Everything else the enricher already does on reprocess (committing
  # safe fills that were held hostage by the publisher conflict, closing
  # the stale PendingDecision via SourceRecorder.resolve_stale_conflict)
  # falls out for free.
  module Publishers
    VOCABULARY = "publisher"

    Result = Struct.new(:editions_rewritten, :editions_reprocessed, :conflicts_cleared, keyword_init: true)

    class << self
      def label = "Publishers"

      def controlled_fields = %w[Edition#publisher]

      # Affected-record counts for the settings screen.
      def usage(term)
        keys = term.authority_variants.pluck(:normalized_label)
        {
          editions: editions_matching(keys).count,
          pending_conflicts: pending_publisher_conflicts.count { |d| resolvable_by?(d, term) }
        }
      end

      # Called after a term is established or a variant registered.
      def apply(term)
        keys = term.authority_variants.pluck(:normalized_label)
        rewritten = rewrite(editions_matching(keys), term.preferred_label)
        counts = reprocess(affected_edition_ids(term))
        notify("Publisher term established", term.preferred_label, term.variant_labels,
               rewritten: rewritten, **counts)
        Result.new(editions_rewritten: rewritten, **counts)
      end

      # Called after a term or variant is removed. `removed_labels` are
      # the strings that no longer resolve; the caller captures them
      # before deleting. Editions keep whatever value they hold — only
      # enrichment is re-run, so a genuine conflict comes back.
      def retract(removed_labels:, preferred_label:)
        keys = removed_labels.map { |l| Authority.normalize(l) }
        ids = EnrichmentRecord.where(entity_type: "Edition", provider: "isfdb")
                              .filter_map { |er| er.entity_id if keys.include?(Authority.normalize(er.fields["publisher"])) }
        ids |= editions_matching(keys).ids
        counts = reprocess(ids)
        notify("Publisher term retracted", preferred_label, removed_labels,
               rewritten: 0, **counts)
        Result.new(editions_rewritten: 0, **counts)
      end

      private

      def editions_matching(normalized_keys)
        return Edition.none if normalized_keys.empty?

        Edition.where.not(publisher: nil)
               .select { |e| normalized_keys.include?(Authority.normalize(e.publisher)) }
               .then { |list| Edition.where(id: list.map(&:id)) }
      end

      def rewrite(editions, preferred)
        editions.filter_map do |e|
          next if e.publisher == preferred

          e.update!(publisher: preferred)
          e.id
        end.size
      end

      # Put each edition back through ISFDB reprocess, then drop "publisher"
      # from any bundled decision that still lists it but no longer
      # genuinely conflicts. Counts how many publisher conflicts clear.
      def reprocess(edition_ids)
        edition_ids = edition_ids.to_a.uniq
        before = editions_with_publisher_conflict(edition_ids)

        Edition.where(id: edition_ids).find_each do |edition|
          payload = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.raw_payload
          next if payload.blank?

          Enrichment::IsfdbEditionEnricher.reprocess(edition, payload)
          prune_settled_publisher(edition)
        end

        after = editions_with_publisher_conflict(edition_ids)
        { editions_reprocessed: edition_ids.size, conflicts_cleared: (before - after).size }
      end

      def editions_with_publisher_conflict(edition_ids)
        PendingDecision.pending.where(kind: "enrichment_conflict")
                       .filter_map { |d| d.payload["entity_id"] if edition_ids.include?(d.payload["entity_id"]) && (d.payload["fields"] || []).include?("publisher") }
                       .to_set
      end

      # A reused bundled decision keeps its original field list even after
      # a re-enrich settles one of those fields — SourceRecorder never
      # refreshes it. Drop "publisher" once the enricher agrees it's no
      # longer in conflict; resolve_stale_conflict already handled the
      # case where nothing conflicts at all.
      def prune_settled_publisher(edition)
        decision = PendingDecision.pending.where(kind: "enrichment_conflict")
                                  .find { |d| d.payload["entity_id"] == edition.id && (d.payload["fields"] || []).include?("publisher") }
        return unless decision

        proposed = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.fields&.dig("publisher")
        return if Enrichment::IsfdbEditionEnricher.plan_publisher_for(edition, proposed).action == :conflict

        decision.update!(payload: decision.payload.merge("fields" => decision.payload["fields"] - [ "publisher" ]))
      end

      def pending_publisher_conflicts
        PendingDecision.pending.where(kind: "enrichment_conflict")
                       .select { |d| (d.payload["fields"] || []).include?("publisher") }
      end

      def resolvable_by?(decision, term)
        edition = Edition.find_by(id: decision.payload["entity_id"])
        proposed = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.fields&.dig("publisher")
        return false if proposed.blank?

        term.authority_variants.pluck(:normalized_label).include?(Authority.normalize(proposed))
      end

      def affected_edition_ids(term)
        keys = term.authority_variants.pluck(:normalized_label)
        ids = editions_matching(keys).ids
        ids |= pending_publisher_conflicts.filter_map { |d| d.payload["entity_id"] if resolvable_by?(d, term) }
        ids
      end

      def notify(title, preferred, variants, rewritten:, editions_reprocessed:, conflicts_cleared:)
        Notifications.notify(Notifications::Event.new(
          kind: :authority_control, level: :info, title: title,
          fields: {
            "Vocabulary" => "publisher",
            "Preferred" => preferred,
            "Variants" => Array(variants).join(", ").presence || "—",
            "Editions rewritten" => rewritten,
            "Editions re-enriched" => editions_reprocessed,
            "Conflicts cleared" => conflicts_cleared
          }
        ))
      end
    end
  end
end

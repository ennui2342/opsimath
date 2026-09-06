module Authority
  # The "publisher" vocabulary handler — the catalogue-side behaviour that
  # sits behind Authority's generic model.
  #
  # Establishing a term:
  #   1. rewrite  — editions whose `publisher` is a *non-preferred* variant
  #      of the term take the preferred form (decision: "establishing a
  #      term rewrites the catalogue").
  #   2. re-enrich — a tight set (the rewritten editions + editions with a
  #      pending publisher conflict this term settles) goes back through
  #      Enrichment::IsfdbEditionEnricher.reprocess. With the term in place
  #      the publisher no longer conflicts, so SourceRecorder either drops
  #      it from the bundled decision or, if it was the only thing wrong,
  #      resolves the decision (committing the safe fills that were held
  #      hostage — the same outcome as accepting it). Editions already on
  #      the preferred form with nothing pending are left alone.
  #
  # Retracting: no rollback of the *whole* record, but the publisher value
  # is restored from its original source's EnrichmentRecord (Mark: "the
  # data is always recoverable in the metadata records") so the re-enrich
  # actually re-raises the conflict rather than seeing agreement.
  module Publishers
    VOCABULARY = "publisher"

    Result = Struct.new(:editions_rewritten, :editions_reprocessed, :conflicts_cleared, :conflicts_raised,
                        keyword_init: true)

    class << self
      def label = "Publishers"

      def controlled_fields = %w[Edition#publisher]

      def usage(term)
        {
          editions: editions_on_variants(term, include_preferred: true).count,
          pending_conflicts: settleable_conflicts(term).size
        }
      end

      def apply(term)
        rewritten = rewrite(editions_on_variants(term), term.preferred_label)
        touched = rewritten | settleable_conflicts(term).map { |d| d.payload["entity_id"] }

        before = pending_publisher_conflict_ids
        reprocessed = reprocess(touched)
        after = pending_publisher_conflict_ids

        result = Result.new(editions_rewritten: rewritten.size, editions_reprocessed: reprocessed,
                            conflicts_cleared: (before - after).size, conflicts_raised: (after - before).size)
        notify("Publisher term established", term.preferred_label, term.variant_labels, result)
        result
      end

      # `removed_labels` are the strings that no longer resolve (captured
      # by the caller before the delete). Editions stuck on one of them —
      # or on a now-orphaned preferred form — have their publisher put
      # back to what their source's EnrichmentRecord says, then are
      # re-enriched so a genuine conflict re-appears.
      def retract(removed_labels:, preferred_label:)
        keys = removed_labels.map { |l| Authority.normalize(l) }.to_set
        restored = restore_publisher(editions_with_normalized_publisher(keys))
        also = EnrichmentRecord.where(entity_type: "Edition", provider: "isfdb")
                               .filter_map { |er| er.entity_id if keys.include?(Authority.normalize(er.fields["publisher"])) }

        before = pending_publisher_conflict_ids
        reprocessed = reprocess(restored | also)
        after = pending_publisher_conflict_ids

        result = Result.new(editions_rewritten: 0, editions_reprocessed: reprocessed,
                            conflicts_cleared: (before - after).size, conflicts_raised: (after - before).size)
        notify("Publisher term retracted", preferred_label, removed_labels, result)
        result
      end

      private

      # Editions whose publisher normalises to one of the term's variants.
      # `include_preferred:` controls whether the preferred form itself
      # counts (usage counts do; the rewrite doesn't — nothing to rewrite).
      def editions_on_variants(term, include_preferred: false)
        keys = term.authority_variants.pluck(:normalized_label).to_set
        keys.delete(Authority.normalize(term.preferred_label)) unless include_preferred
        editions_with_normalized_publisher(keys)
      end

      def editions_with_normalized_publisher(keys)
        return [] if keys.empty?

        Edition.where.not(publisher: [ nil, "" ])
               .filter_map { |e| e.id if keys.include?(Authority.normalize(e.publisher)) }
      end

      def rewrite(edition_ids, preferred)
        Edition.where(id: edition_ids).filter_map do |e|
          next if e.publisher == preferred

          e.update!(publisher: preferred)
          e.id
        end
      end

      # Reset each edition's publisher to the value recorded by whichever
      # provider field_sources credits it to (falling back to goodreads),
      # when that differs from what's on the edition now.
      def restore_publisher(edition_ids)
        Edition.where(id: edition_ids).filter_map do |e|
          provider = e.field_sources["publisher"].presence || "goodreads"
          original = EnrichmentRecord.latest(entity: e, provider: provider)&.fields&.dig("publisher")
          next if original.blank? || original == e.publisher

          e.update!(publisher: original)
          e.id
        end
      end

      # Pending publisher conflicts whose ISFDB-proposed publisher this
      # term would resolve (regardless of what the edition currently holds).
      def settleable_conflicts(term)
        keys = term.authority_variants.pluck(:normalized_label).to_set
        pending_publisher_conflicts.select do |d|
          proposed = EnrichmentRecord.latest(entity: Edition.find_by(id: d.payload["entity_id"]), provider: "isfdb")&.fields&.dig("publisher")
          proposed.present? && keys.include?(Authority.normalize(proposed))
        end
      end

      def pending_publisher_conflicts
        PendingDecision.pending.where(kind: "enrichment_conflict")
                       .select { |d| (d.payload["fields"] || []).include?("publisher") }
      end

      # Re-run ISFDB enrichment for a tight edition set, no network.
      # Returns how many were actually reprocessed.
      def reprocess(edition_ids)
        edition_ids = edition_ids.to_a.uniq
        n = 0
        Edition.where(id: edition_ids).find_each do |edition|
          payload = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.raw_payload
          next if payload.blank?

          Enrichment::IsfdbEditionEnricher.reprocess(edition, payload)
          prune_settled_publisher(edition)
          n += 1
        end
        n
      end

      # Edition ids that currently have a pending enrichment_conflict
      # listing "publisher" — the before/after set apply and retract diff.
      def pending_publisher_conflict_ids
        pending_publisher_conflicts.map { |d| d.payload["entity_id"] }.to_set
      end

      # A reused bundled decision keeps its original field list even after
      # a re-enrich settles one of those fields (SourceRecorder never
      # refreshes it). Drop "publisher" once the enricher agrees.
      def prune_settled_publisher(edition)
        decision = PendingDecision.pending.where(kind: "enrichment_conflict")
                                  .find { |d| d.payload["entity_id"] == edition.id && (d.payload["fields"] || []).include?("publisher") }
        return unless decision

        proposed = EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.fields&.dig("publisher")
        return if Enrichment::IsfdbEditionEnricher.plan_publisher_for(edition, proposed).action == :conflict

        decision.update!(payload: decision.payload.merge("fields" => decision.payload["fields"] - [ "publisher" ]))
      end

      def notify(title, preferred, variants, result)
        Notifications.notify(Notifications::Event.new(
          kind: :authority_control, level: :info, title: title,
          fields: {
            "Vocabulary" => "publisher",
            "Preferred" => preferred,
            "Variants" => Array(variants).join(", ").presence || "—",
            "Editions rewritten" => result.editions_rewritten,
            "Editions re-checked" => result.editions_reprocessed,
            "Conflicts cleared" => result.conflicts_cleared,
            "Conflicts re-raised" => result.conflicts_raised
          }
        ))
      end
    end
  end
end

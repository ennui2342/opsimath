module Authority
  # The "publisher" vocabulary handler — the catalogue-side behaviour that
  # sits behind Authority's generic model. Deliberately *surgical*: it
  # only ever touches the publisher field and the "publisher" entry in a
  # decision's bundle. It does not re-run full enrichment, so establishing
  # a publisher term never silently applies other ISFDB fields.
  #
  # apply(term):
  #   1. rewrite  — editions whose `publisher` is a *non-preferred*
  #      variant take the preferred form (decision: "establishing a term
  #      rewrites the catalogue").
  #   2. settle   — for every pending enrichment_conflict where the term
  #      now makes the publisher agree: canonicalise the edition's value
  #      if needed, drop "publisher" from the bundle, and resolve the
  #      decision only if publisher was the *only* thing it disputed.
  #
  # retract(removed_labels:):
  #   1. restore  — each affected edition's publisher goes back to the
  #      value its original source's EnrichmentRecord recorded (Mark:
  #      "the data is always recoverable in the metadata records"), so the
  #      strings genuinely differ again.
  #   2. re-raise — where the publisher now conflicts, put it back in the
  #      decision's bundle (re-opening an accepted decision if that's what
  #      apply left behind).
  module Publishers
    VOCABULARY = "publisher"

    Result = Struct.new(:editions_rewritten, :editions_restored, :conflicts_cleared, :decisions_resolved,
                        :conflicts_raised, keyword_init: true) do
      def self.blank = new(editions_rewritten: 0, editions_restored: 0, conflicts_cleared: 0,
                           decisions_resolved: 0, conflicts_raised: 0)
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

      def apply(term)
        result = Result.blank
        # decide which decisions this term actually bridges *before* the
        # rewrite makes the strings trivially equal
        to_settle = publisher_conflicts.select { |d| term_bridges?(d, term) }

        result.editions_rewritten = rewrite(editions_on_variants(term), term.preferred_label).size

        to_settle.each do |decision|
          decision.reload
          edition = Edition.find(decision.payload["entity_id"])
          canonicalise(edition)
          if drop_publisher(decision)
            result.decisions_resolved += 1
          else
            result.conflicts_cleared += 1
          end
        end

        notify("Publisher term established", term, result)
        result
      end

      def retract(removed_labels:, preferred_label:)
        keys = removed_labels.map { |l| Authority.normalize(l) }.to_set
        result = Result.blank
        result.editions_restored = restore(editions_with_normalized_publisher(keys)).size

        # editions still (or now, post-restore) on a string that no longer
        # resolves — the conflict may need to come back
        editions_with_normalized_publisher(keys).each do |edition|
          proposed = isfdb_publisher(edition)
          next if proposed.blank?
          next unless Enrichment::IsfdbEditionEnricher.plan_publisher_for(edition, proposed).action == :conflict

          result.conflicts_raised += 1 if re_raise_publisher(edition)
        end

        notify("Publisher term retracted",
               Struct.new(:preferred_label, :variant_labels).new(preferred_label, removed_labels), result)
        result
      end

      private

      # --- the term's reach ------------------------------------------------

      def editions_on_variants(term, include_preferred: false)
        keys = term.authority_variants.pluck(:normalized_label).to_set
        keys.delete(Authority.normalize(term.preferred_label)) unless include_preferred
        editions_with_normalized_publisher(keys)
      end

      def editions_with_normalized_publisher(keys)
        return [] if keys.empty?

        Edition.where.not(publisher: [ nil, "" ])
               .select { |e| keys.include?(Authority.normalize(e.publisher)) }
      end

      def publisher_conflicts
        PendingDecision.pending.where(kind: "enrichment_conflict")
                       .select { |d| (d.payload["fields"] || []).include?("publisher") }
      end

      # Does this term bridge a *genuine* publisher disagreement on this
      # decision — the edition's value and the ISFDB value are different
      # strings that both resolve to the term? (Not "publisher happens to
      # be in the bundle but the two strings already matched", which is
      # just a stale entry this term had nothing to do with.)
      def term_bridges?(decision, term)
        edition = Edition.find_by(id: decision.payload["entity_id"])
        proposed = isfdb_publisher(edition)
        return false if edition.nil? || proposed.blank?

        keys = term.authority_variants.pluck(:normalized_label).to_set
        current_key = Authority.normalize(edition.publisher)
        proposed_key = Authority.normalize(proposed)
        current_key != proposed_key && keys.include?(current_key) && keys.include?(proposed_key)
      end

      def isfdb_publisher(edition)
        EnrichmentRecord.latest(entity: edition, provider: "isfdb")&.fields&.dig("publisher")
      end

      # --- edits ---------------------------------------------------------

      def rewrite(editions, preferred)
        editions.filter_map do |e|
          next if e.publisher == preferred

          e.update!(publisher: preferred)
          e
        end
      end

      # If the enricher would now refine the edition's own publisher to a
      # preferred form, do that write (same as accepting the field would).
      def canonicalise(edition)
        plan = Enrichment::IsfdbEditionEnricher.plan_publisher_for(edition, isfdb_publisher(edition))
        return unless plan.action == :refine

        edition.update!(publisher: plan.value,
                        field_sources: edition.field_sources.merge("publisher" => "isfdb"))
      end

      # Drop "publisher" from a decision's bundle. Returns true if that
      # emptied it (→ decision resolved), false if other fields remain.
      def drop_publisher(decision)
        remaining = (decision.payload["fields"] || []) - [ "publisher" ]
        if remaining.empty?
          decision.update!(status: "accepted", resolved_at: Time.current, payload: decision.payload.merge("fields" => remaining))
          true
        else
          decision.update!(payload: decision.payload.merge("fields" => remaining))
          false
        end
      end

      def restore(editions)
        editions.filter_map do |e|
          provider = e.field_sources["publisher"].presence || "goodreads"
          original = EnrichmentRecord.latest(entity: e, provider: provider)&.fields&.dig("publisher")
          next if original.blank? || original == e.publisher

          e.update!(publisher: original)
          e
        end
      end

      # Put "publisher" back on the edition's enrichment_conflict —
      # re-opening the one apply resolved, or the still-pending one apply
      # only pruned. Returns true only if it actually changed something.
      def re_raise_publisher(edition)
        decision = PendingDecision.where(kind: "enrichment_conflict")
                                  .where("payload @> ?", { entity_type: "Edition", entity_id: edition.id, source: "isfdb" }.to_json)
                                  .order(updated_at: :desc).first
        return false unless decision

        fields = ((decision.payload["fields"] || []) | [ "publisher" ])
        return false if decision.pending? && fields == decision.payload["fields"] # already listed & pending

        decision.update!(status: "pending", resolved_at: nil, payload: decision.payload.merge("fields" => fields))
        true
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
            "Conflicts cleared" => result.conflicts_cleared,
            "Decisions resolved" => result.decisions_resolved,
            "Conflicts re-raised" => result.conflicts_raised
          }.compact
        ))
      end
    end
  end
end

module ReviewQueue
  # The existing review queue under the anchored-editions model
  # (docs/CATALOG.md, "Anchored editions" → "The existing queue"): for an
  # edition anchored to an ISFDB printing, ISFDB wins.
  #
  # - An ISFDB field conflict is accepted — ISFDB's values for every field
  #   it proposed, through the review screen's own accept path —
  #   **unless** it looks like the anchor is the wrong printing: the dates
  #   2+ years apart, or the formats differing. That's an identity question,
  #   not a data-quality one, so it stays pending, flagged
  #   (payload "identity_question"), for Mark to settle with the edition
  #   picker ("Which is yours?").
  # - A Goodreads conflict (Goodreads proposing over what's on file) is
  #   rejected.
  # - Unanchored editions, printing choices and anything else: untouched.
  #
  # `plan` is a dry run; `apply` does it. Edition keeps paper_trail
  # versions, so every change is recoverable.
  class IsfdbWins
    YEAR_GAP = 2
    Outcome = Struct.new(:decision, :action, :reason, keyword_init: true) # action: :accept | :identity_question | :reject | :skip

    def self.plan(scope = default_scope) = scope.to_a.map { |d| classify(d) }

    def self.apply(scope = default_scope)
      plan(scope).each do |o|
        case o.action
        when :accept then Enrichment::PendingDecisionResolver.accept(o.decision)
        when :reject then Enrichment::PendingDecisionResolver.reject(o.decision)
        when :identity_question then o.decision.update!(payload: o.decision.payload.merge("identity_question" => o.reason))
        end
      end
    end

    def self.default_scope = PendingDecision.pending.where(kind: "enrichment_conflict")

    def self.classify(decision)
      edition = decision.entity
      return outcome(decision, :skip, "not about an edition") unless edition.is_a?(Edition)
      return outcome(decision, :skip, "not anchored to an ISFDB printing") unless edition.edition_identifiers.exists?(id_type: "isfdb")

      case decision.payload["source"]
      when "goodreads" then outcome(decision, :reject, "ISFDB wins over Goodreads")
      when "isfdb" then isfdb_outcome(decision, edition)
      else outcome(decision, :skip, "source #{decision.payload['source']}")
      end
    end

    def self.isfdb_outcome(decision, edition)
      record = EnrichmentRecord.latest(entity: edition, provider: "isfdb")
      return outcome(decision, :skip, "no ISFDB record on file") unless record

      ours, theirs = edition.publish_date.to_s[0, 4].to_i, record.fields["publish_date"].to_s[0, 4].to_i
      if ours.positive? && theirs.positive? && (ours - theirs).abs >= YEAR_GAP
        return outcome(decision, :identity_question, "ISFDB's printing is dated #{theirs}; yours #{ours}")
      end

      fields = Array(decision.payload["fields"])
      if fields.include?("format") && edition.format.present? && record.fields["format"].present? && edition.format != record.fields["format"]
        return outcome(decision, :identity_question, "ISFDB's printing is a #{record.fields['format']}; yours a #{edition.format}")
      end

      outcome(decision, :accept, "ISFDB wins: #{fields.join(', ')}")
    end

    def self.outcome(decision, action, reason) = Outcome.new(decision:, action:, reason:)
  end
end

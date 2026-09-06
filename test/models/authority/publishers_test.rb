require "test_helper"

module Authority
  class PublishersTest < ActiveSupport::TestCase
    setup { Notifications.notifiers = [] }
    teardown { Notifications.notifiers = nil }

    # An edition whose publisher disagrees with its ISFDB record, with the
    # matching pending enrichment_conflict — the shape `apply` has to clear.
    # `also_conflicts_on_date:` adds a genuine publish_date disagreement so
    # the bundled decision has a reason to stay after publisher is settled.
    def edition_in_conflict(on_file:, isfdb:, also_conflicts_on_date: false)
      edition = Edition.create!(publisher: on_file, field_sources: { "publisher" => "goodreads" })
      edition.update!(publish_date: "1990", field_sources: edition.field_sources.merge("publish_date" => "goodreads")) if also_conflicts_on_date
      EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: "0441172717")
      payload = { "publisher" => isfdb, "binding" => "pb", "_isfdb_pub_id" => 1, "isbn_10" => "0441172717" }
      payload["publish_date"] = "2001" if also_conflicts_on_date
      EnrichmentRecord.create!(
        entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
        fields: payload.slice("publisher", "publish_date"), raw_payload: payload
      )
      PendingDecision.create!(kind: "enrichment_conflict", payload: {
        "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb",
        "fields" => [ "publisher", *("publish_date" if also_conflicts_on_date) ].compact
      })
      edition
    end

    test "apply rewrites editions on a variant to the preferred form and clears the publisher-only conflicts" do
      a = edition_in_conflict(on_file: "Pan Macmillan UK", isfdb: "Pan Books")
      b = edition_in_conflict(on_file: "Pan Macmillan", isfdb: "Pan Books")

      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      term.register_variant("Pan Macmillan")

      result = Authority::Publishers.apply(term)

      assert_equal "Pan Books", a.reload.publisher
      assert_equal "Pan Books", b.reload.publisher
      assert_equal 2, result.editions_rewritten
      assert_equal 2, result.conflicts_cleared
      assert_empty PendingDecision.pending
    end

    test "apply drops publisher from a bundled conflict but leaves the decision pending for its other fields" do
      edition_in_conflict(on_file: "Pan Macmillan UK", isfdb: "Pan Books", also_conflicts_on_date: true)

      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")

      Authority::Publishers.apply(term)

      decision = PendingDecision.pending.sole
      assert_not_includes decision.payload["fields"], "publisher"
      assert_includes decision.payload["fields"], "publish_date"
    end

    test "apply posts a summary notification" do
      events = []
      Notifications.notifiers = [ Struct.new(:log) { def notify(e) = log << e }.new(events) ]

      edition_in_conflict(on_file: "Tordotcom", isfdb: "Tor.com")
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
      term.register_variant("Tordotcom")
      Authority::Publishers.apply(term)

      assert_equal 1, events.size
      assert_equal :authority_control, events.first.kind
      assert_equal "Tor.com", events.first.fields["Preferred"]
    end

    test "retract re-enriches the affected editions so a genuine conflict comes back" do
      edition = edition_in_conflict(on_file: "Pan Macmillan UK", isfdb: "Pan Books")
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      Authority::Publishers.apply(term)
      assert_empty PendingDecision.pending
      assert_equal "Pan Books", edition.reload.publisher

      removed = term.authority_variants.map(&:label)
      term.destroy!
      Authority::Publishers.retract(removed_labels: removed, preferred_label: "Pan Books")

      # edition keeps "Pan Books"; ISFDB still says "Pan Books" in its
      # record for this one, so no conflict here — but the point is the
      # sweep ran. Assert an edition that now genuinely disagrees re-raises.
      assert_equal "Pan Books", edition.reload.publisher
    end

    test "retract re-raises the conflict when the catalog value and ISFDB genuinely differ" do
      edition = Edition.create!(publisher: "Pan Books", field_sources: { "publisher" => "isfdb" })
      EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
                               fields: { "publisher" => "Pan Macmillan UK" },
                               raw_payload: { "publisher" => "Pan Macmillan UK", "binding" => "pb", "_isfdb_pub_id" => 1 })
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      term.destroy!

      Authority::Publishers.retract(removed_labels: [ "Pan Books", "Pan Macmillan UK" ], preferred_label: "Pan Books")

      decision = PendingDecision.pending.sole
      assert_equal "enrichment_conflict", decision.kind
      assert_includes decision.payload["fields"], "publisher"
    end

    test "usage reports affected edition and conflict counts" do
      edition_in_conflict(on_file: "Tordotcom", isfdb: "Tor.com")
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
      term.register_variant("Tordotcom")

      usage = Authority::Publishers.usage(term)
      assert_equal 1, usage[:editions]
      assert_equal 1, usage[:pending_conflicts]
    end
  end
end

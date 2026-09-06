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
      # the original source, so retract can restore the pre-term value
      EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "g", fetched_at: 1.day.ago,
                               fields: { "publisher" => on_file }, raw_payload: { "publisher" => on_file })
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

    test "apply drops publisher from a bundled conflict but leaves the decision pending for its other genuine conflicts" do
      edition_in_conflict(on_file: "Pan Macmillan UK", isfdb: "Pan Books", also_conflicts_on_date: true)

      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")

      Authority::Publishers.apply(term)

      decision = PendingDecision.pending.sole
      assert_not_includes decision.payload["fields"], "publisher"
      assert_includes decision.payload["fields"], "publish_date"
    end

    test "apply lets the rest of the fetch complete when publisher was the only real conflict — safe fills apply, decision resolves" do
      edition = Edition.create!(publisher: "Pan Macmillan UK", field_sources: { "publisher" => "goodreads" })
      EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "g", fetched_at: 1.day.ago,
                               fields: { "publisher" => "Pan Macmillan UK" }, raw_payload: { "publisher" => "Pan Macmillan UK" })
      EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
                               fields: { "publisher" => "Pan Books", "language" => "eng", "page_count" => 320 },
                               raw_payload: { "publisher" => "Pan Books", "language" => "eng", "page_count" => 320, "binding" => "pb", "_isfdb_pub_id" => 1 })
      PendingDecision.create!(kind: "enrichment_conflict", payload: {
        "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb",
        "fields" => %w[publisher language page_count]
      })

      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      Authority::Publishers.apply(term)

      edition.reload
      assert_equal "Pan Books", edition.publisher
      assert_equal "eng", edition.language      # the blank fill that was held hostage now applies
      assert_equal 320, edition.page_count
      assert_empty PendingDecision.pending      # nothing left to review
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

    test "retract restores the pre-term publisher value and re-raises the conflict" do
      edition = edition_in_conflict(on_file: "Palgrave Macmillan Ltd", isfdb: "Tor / Pan Macmillan UK")
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor / Pan Macmillan UK")
      term.register_variant("Palgrave Macmillan Ltd")
      Authority::Publishers.apply(term)
      assert_equal "Tor / Pan Macmillan UK", edition.reload.publisher
      assert_empty PendingDecision.pending

      removed = term.authority_variants.map(&:label)
      term.destroy!
      result = Authority::Publishers.retract(removed_labels: removed, preferred_label: "Tor / Pan Macmillan UK")

      assert_equal "Palgrave Macmillan Ltd", edition.reload.publisher # restored from the goodreads record
      decision = PendingDecision.pending.sole
      assert_equal "enrichment_conflict", decision.kind
      assert_includes decision.payload["fields"], "publisher"
      assert_equal 1, result.conflicts_raised
    end

    test "preview separates the rewrites ISFDB corroborates from the ones nothing would catch" do
      # ISFDB agrees this is the term
      ok = Edition.create!(publisher: "Pan Books Ltd")
      EnrichmentRecord.create!(entity: ok, provider: "isfdb", external_id: "1", fetched_at: Time.current,
                               fields: { "publisher" => "Tor / Pan Macmillan UK" }, raw_payload: {})
      # ISFDB names a different publisher
      contra = Edition.create!(publisher: "Pan Books Ltd")
      EnrichmentRecord.create!(entity: contra, provider: "isfdb", external_id: "2", fetched_at: Time.current,
                               fields: { "publisher" => "Pan Books" }, raw_payload: {})
      # no ISFDB record at all
      blind = Edition.create!(publisher: "Pan Books Ltd")

      preview = Authority::Publishers.preview(preferred: "Tor / Pan Macmillan UK", variant_labels: [ "Pan Books Ltd" ])

      assert_equal 3, preview.rewritten
      assert_equal 1, preview.corroborated
      assert_equal 1, preview.contradicted
      assert_equal 1, preview.unmatched
      assert preview.risky?
      assert_equal %i[contradicted unmatched corroborated],
                   preview.editions.map { |e| e[:status] } # contradicted/unmatched surfaced first
    end

    test "preview excludes editions already on the preferred form" do
      Edition.create!(publisher: "Tor / Pan Macmillan UK")
      on_variant = Edition.create!(publisher: "Pan Books Ltd")

      preview = Authority::Publishers.preview(preferred: "Tor / Pan Macmillan UK", variant_labels: [ "Pan Books Ltd", "Tor / Pan Macmillan UK" ])

      assert_equal [ on_variant.id ], preview.editions.map { |e| e[:id] }
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

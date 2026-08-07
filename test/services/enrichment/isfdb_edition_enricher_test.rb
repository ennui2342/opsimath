require "test_helper"

module Enrichment
  class IsfdbEditionEnricherTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    # Real response shape, confirmed live (curl against the actual
    # adapter after wiring up its Ingress) for ISBN 0441172717.
    DUNE_RESPONSE = {
      provider: "isfdb", provider_display: "ISFDB", title: "Dune", subtitle: "",
      authors: [ "Frank Herbert" ], publisher: "Ace Books", publish_date: "2010",
      isbn_10: "0441172717", isbn_13: "9780441172719", description: "",
      cover_url: "https://isfdb.org/covers/dune.jpg", language: "eng", page_count: 883,
      categories: [], binding: "pb",
      _isfdb_pub_id: 426303, _isfdb_title_id: 2036, _isfdb_series_id: 869, _isfdb_series_num: 1
    }.freeze

    setup do
      @client = Isfdb::Client.new(base_url: BASE_URL)
      @edition = Edition.create!(format: "paperback")
      EditionIdentifier.create!(edition: @edition, id_type: "isbn10", value: "0441172717")
    end

    test "skips an edition with no isbn identifier at all" do
      bare_edition = Edition.create!(format: "paperback")

      result = IsfdbEditionEnricher.enrich(bare_edition, client: @client)

      assert_equal :skipped, result.status
      assert_equal 0, EnrichmentRecord.count
    end

    test "skips when isfdb-adapter has no match for this isbn (a real 404)" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 404)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :skipped, result.status
    end

    test "reports failure without raising on a service error" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 503)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :failed, result.status
      assert_match(/503/, result.message)
    end

    test "records an EnrichmentRecord and fills blank fields on a real match" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "fake-jpeg-bytes", headers: { "Content-Type" => "image/jpeg" })

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal :success, result.status

      record = EnrichmentRecord.sole
      assert_equal "Edition", record.entity_type
      assert_equal @edition.id, record.entity_id
      assert_equal "isfdb", record.provider
      assert_equal "426303", record.external_id
      assert_equal "Dune", record.raw_payload["title"]

      assert_equal "Ace Books", @edition.publisher
      assert_equal "eng", @edition.language
      assert_equal 883, @edition.page_count
      assert_equal "2010", @edition.publish_date
      assert_equal "isfdb", @edition.field_sources["publisher"]

      # "pb" -> paperback/mass_market; format was already "paperback" so
      # that's :unchanged, but format_detail was blank so it gets filled.
      assert_equal "paperback", @edition.format
      assert_equal "mass_market", @edition.format_detail

      assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "426303")
      assert @edition.cover_image.attached?
    end

    test "reprocess re-applies an already-fetched payload without a new EnrichmentRecord or network call" do
      data = JSON.parse(DUNE_RESPONSE.to_json) # string-keyed, matching a real stored raw_payload
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.reprocess(@edition, data)
      @edition.reload

      assert_equal 0, EnrichmentRecord.count # no new fetch happened
      assert_equal "Ace Books", @edition.publisher
      assert_equal "2010", @edition.publish_date
      assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "426303")
    end

    test "a genuinely conflicting non-blank field creates a PendingDecision instead of overwriting" do
      @edition.update!(publisher: "Berkley Windhover")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Berkley Windhover", @edition.reload.publisher
      assert PendingDecision.exists?(kind: "enrichment_field_conflict")
    end

    test "a generic-suffix publisher variant is merged toward the more complete form, real example" do
      @edition.update!(publisher: "Tor")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Tor Books").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Tor Books", @edition.reload.publisher
      assert_equal "isfdb", @edition.field_sources["publisher"]
      assert_equal 0, PendingDecision.count
    end

    test "the shorter side of a generic-suffix variant is left alone — already the more complete form" do
      @edition.update!(publisher: "DAW Books")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "DAW").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "DAW Books", @edition.reload.publisher
      assert_equal 0, PendingDecision.count
    end

    test "an isolated region-flavored publisher variant IS merged — it's an ISBN-keyed fact about this exact printing, not a guess" do
      @edition.update!(publisher: "Orbit")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Orbit (US)").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Orbit (US)", @edition.reload.publisher
      assert_equal 0, PendingDecision.count
    end

    test "two fields disagreeing at once bundles into one edition-mismatch review, neither applied nor split into separate field decisions" do
      @edition.update!(publisher: "Berkley Windhover", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "1979-06").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # untouched
      assert_equal "1978", @edition.publish_date # untouched
      assert_equal 0, PendingDecision.where(kind: "enrichment_field_conflict").count

      decision = PendingDecision.where(kind: "enrichment_edition_mismatch").sole
      assert_equal "Edition", decision.payload["entity_type"]
      assert_equal @edition.id, decision.payload["entity_id"]
      fields = decision.payload["fields"].index_by { |f| f["field"] }
      assert_equal "Berkley Windhover", fields["publisher"]["current_value"]
      assert_equal "Ace Books", fields["publisher"]["proposed"]
      assert_equal "1978", fields["publish_date"]["current_value"]
      assert_equal "1979-06", fields["publish_date"]["proposed"]
    end

    test "a would-be-safe refinement is held back too when it co-occurs with a genuine conflict on the same edition" do
      # publisher here would be a safe generic-suffix refinement in
      # isolation ("Tor" -> "Tor Books"), but publish_date genuinely
      # conflicts on the same edition — real data shows this co-occurrence
      # pattern means the whole ISBN match likely describes a different
      # specific printing, so the refinement isn't trusted either.
      @edition.update!(publisher: "Tor", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Tor Books", publish_date: "1985").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Tor", @edition.publisher # NOT merged, even though it looked safe in isolation
      assert_equal "1978", @edition.publish_date
      assert PendingDecision.exists?(kind: "enrichment_edition_mismatch")
    end

    test "one genuine conflict alongside an unrelated blank fill still applies the fill and flags only the conflict normally" do
      @edition.update!(publisher: "Berkley Windhover") # language and publish_date left blank
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Ace Books").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # the one real conflict, untouched
      assert_equal "eng", @edition.language # unrelated fill still applies
      assert_equal "2010", @edition.publish_date # unrelated fill still applies
      assert_equal 0, PendingDecision.where(kind: "enrichment_edition_mismatch").count
      assert PendingDecision.exists?(kind: "enrichment_field_conflict", status: "pending")
    end

    test "a cover download failure doesn't block the other fields from applying" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 500)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_not @edition.reload.cover_image.attached?
      assert_equal "Ace Books", @edition.publisher
    end

    test "a cover that differs from the one already attached, with no other field disagreeing, still bundles into an edition mismatch" do
      @edition.cover_image.attach(io: StringIO.new("old-cover-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "new-cover-bytes-from-isfdb", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "old-cover-bytes", @edition.cover_image.download # untouched pending review
      assert @edition.candidate_cover_image.attached?
      assert_equal "new-cover-bytes-from-isfdb", @edition.candidate_cover_image.download

      decision = PendingDecision.where(kind: "enrichment_edition_mismatch").sole
      assert_equal [ { "field" => "cover_image" } ], decision.payload["fields"]
    end

    test "a cover that's byte-identical to the one already attached is a no-op, not noise" do
      @edition.cover_image.attach(io: StringIO.new("same-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "same-bytes", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_not @edition.candidate_cover_image.attached?
      assert_equal 0, PendingDecision.count
    end

    test "a cover conflict co-occurring with a real field conflict bundles into one mismatch with both entries" do
      @edition.update!(publisher: "Berkley Windhover")
      @edition.cover_image.attach(io: StringIO.new("old-cover-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Ace Books").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "new-cover-bytes-from-isfdb", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # untouched
      assert @edition.candidate_cover_image.attached?

      decision = PendingDecision.where(kind: "enrichment_edition_mismatch").sole
      field_names = decision.payload["fields"].map { |f| f["field"] }
      assert_equal %w[publisher cover_image].sort, field_names.sort
    end

    test "re-enriching an edition with an already-unresolved edition mismatch reuses the decision instead of spawning a second one" do
      @edition.update!(publisher: "Berkley Windhover", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "1979-06").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal 1, PendingDecision.where(kind: "enrichment_edition_mismatch").count
    end

    test "a more precise publish_date from isfdb is applied as a refinement, not flagged as a conflict" do
      @edition.update!(publish_date: "2010")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publish_date: "2010-06").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010-06", @edition.reload.publish_date
      assert_equal "isfdb", @edition.field_sources["publish_date"]
      assert_equal 0, PendingDecision.where(kind: "enrichment_field_conflict").where("payload ->> 'field' = ?", "publish_date").count
    end

    test "a less precise publish_date from isfdb is left alone — we already know more" do
      @edition.update!(publish_date: "2010-06-15")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.merge(publish_date: "2010").to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010-06-15", @edition.reload.publish_date
      assert_equal 0, PendingDecision.count
    end

    test "the same publish_date value at the same precision is a no-op, not a conflict" do
      @edition.update!(publish_date: "2010")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010", @edition.reload.publish_date
      assert_equal 0, PendingDecision.count
    end

    test "a genuinely different publish_date (neither value extends the other) is a real conflict" do
      @edition.update!(publish_date: "2011")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json) # "2010"
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2011", @edition.reload.publish_date # untouched
      decision = PendingDecision.where(kind: "enrichment_field_conflict").where("payload ->> 'field' = ?", "publish_date").sole
      assert_equal "2011", decision.payload["current_value"]
      assert_equal "2010", decision.payload["proposed"].first["value"]
    end

    test "unmapped pub_ptype values are left alone rather than guessed at" do
      response = DUNE_RESPONSE.merge(binding: "quarto")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: response.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "paperback", @edition.reload.format # untouched default, not guessed from "quarto"
      assert_nil @edition.format_detail
    end
  end
end

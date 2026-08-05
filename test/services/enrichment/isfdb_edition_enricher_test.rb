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
      assert_equal Date.new(2010, 1, 1), @edition.publish_date
      assert_equal "year", @edition.publish_date_precision
      assert_equal "isfdb", @edition.field_sources["publisher"]

      # "pb" -> paperback/mass_market; format was already "paperback" so
      # that's :unchanged, but format_detail was blank so it gets filled.
      assert_equal "paperback", @edition.format
      assert_equal "mass_market", @edition.format_detail

      assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "426303")
      assert @edition.cover_image.attached?
    end

    test "a genuinely conflicting non-blank field creates a PendingDecision instead of overwriting" do
      @edition.update!(publisher: "Berkley Windhover")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Berkley Windhover", @edition.reload.publisher
      assert PendingDecision.exists?(kind: "enrichment_field_conflict")
    end

    test "a cover download failure doesn't block the other fields from applying" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717").to_return(status: 200, body: DUNE_RESPONSE.to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 500)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_not @edition.reload.cover_image.attached?
      assert_equal "Ace Books", @edition.publisher
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

require "test_helper"

class IsfdbEnrichmentJobTest < ActiveSupport::TestCase
  BASE_URL = ENV.fetch("ISFDB_ADAPTER_URL")

  DUNE_RESPONSE = {
    provider: "isfdb", title: "Dune", authors: [ "Frank Herbert" ], publisher: "Ace Books",
    publish_date: "2010", isbn_10: "0441172717", isbn_13: "9780441172719", description: "",
    cover_url: "", language: "eng", page_count: 883, categories: [], binding: "pb",
    _isfdb_pub_id: 426303
  }.freeze

  test "enriches editions with an isbn, skips those without one or already enriched" do
    with_isbn = Edition.create!(format: "paperback")
    EditionIdentifier.create!(edition: with_isbn, id_type: "isbn10", value: "0441172717")

    without_isbn = Edition.create!(format: "paperback")

    already_enriched = Edition.create!(format: "paperback")
    EditionIdentifier.create!(edition: already_enriched, id_type: "isbn10", value: "1111111111")
    EnrichmentRecord.create!(entity: already_enriched, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {})

    stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)

    counts = IsfdbEnrichmentJob.perform_now

    assert_equal 1, counts.success
    assert_equal 0, counts.failed
    assert_equal 0, counts.skipped # without_isbn/already_enriched are excluded from scope entirely, not "skipped" outcomes

    assert_equal "Ace Books", with_isbn.reload.publisher
    assert_not_requested(:get, /isbn\/1111111111/) # already-enriched edition never re-queried

    job_item = JobItem.sole
    assert_equal "success", job_item.status
    assert_equal with_isbn, job_item.entity
    assert_not_nil job_item.run_id
  end

  test "records a failed JobItem without raising when isfdb-adapter errors" do
    edition = Edition.create!(format: "paperback")
    EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: "0441172717")
    stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 503)

    counts = IsfdbEnrichmentJob.perform_now

    assert_equal 1, counts.failed
    assert_equal "failed", JobItem.sole.status
  end
end

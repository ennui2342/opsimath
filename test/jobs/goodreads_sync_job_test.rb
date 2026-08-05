require "test_helper"

class GoodreadsSyncJobTest < ActiveSupport::TestCase
  class FixtureRssClient
    FILE_NAMES = {
      "wishlist" => "wishlist", "to-read" => "to_read", "currently-reading" => "currently_reading",
      "read" => "read", "did-not-finish" => "did_not_finish"
    }.freeze

    def fetch(shelf)
      client = Goodreads::RssClient.allocate
      body = File.read(Rails.root.join("test/fixtures/files/goodreads_#{FILE_NAMES.fetch(shelf)}_sample.xml"))
      client.send(:parse, body)
    end
  end

  class RecordingNotifier
    attr_reader :events

    def initialize
      @events = []
    end

    def notify(event)
      @events << event
    end
  end

  class RaisingRssClient
    def fetch(_shelf)
      raise "rss fetch failed"
    end
  end

  setup do
    Subject.create!(name: "Fiction", ddc_code: "800")
    # Every real-isbn item this run auto-creates triggers a per-edition
    # ISFDB lookup — stub the mirror as "not found" uniformly, since this
    # test is about notification/JobItem wiring, not enrichment content
    # (already covered in enrichment's own test suite).
    stub_request(:get, /#{Regexp.escape(ENV.fetch("ISFDB_ADAPTER_URL"))}\/isbn\/.*/).to_return(status: 404)
    @recorder = RecordingNotifier.new
    Notifications.notifiers = [ @recorder ]
  end

  teardown do
    Notifications.notifiers = nil
  end

  test "notifies auto_created for a genuinely new book and triggers per-edition ISFDB enrichment" do
    GoodreadsSyncJob.perform_now(rss_client: FixtureRssClient.new)

    auto_created = @recorder.events.select { |e| e.kind == :auto_created }
    assert auto_created.any? { |e| e.title.include?("Children of Memory") }

    edition = Work.find_by!(title: "Children of Memory").editions.sole
    assert_not EnrichmentRecord.exists?(entity_type: "Edition", entity_id: edition.id) # 404'd, not matched — no record created
  end

  test "an ISFDB conflict on a freshly auto-created edition notifies with the book title and the actual field values in dispute" do
    # Children of Memory's real fixture item sets publish_date "2022" at
    # creation (from the feed's own book_published) — stub ISFDB to
    # disagree, the realistic way a brand-new Edition can still hit a
    # genuine :conflict on its very first enrichment pass.
    WebMock.reset!
    stub_request(:get, "#{ENV.fetch("ISFDB_ADAPTER_URL")}/isbn/0316466409").to_return(
      status: 200,
      body: { provider: "isfdb", publisher: nil, publish_date: "2019", binding: nil, page_count: nil, language: nil, cover_url: "", _isfdb_pub_id: 999999 }.to_json
    )
    stub_request(:get, /#{Regexp.escape(ENV.fetch("ISFDB_ADAPTER_URL"))}\/isbn\/(?!0316466409).*/).to_return(status: 404)

    GoodreadsSyncJob.perform_now(rss_client: FixtureRssClient.new)

    conflict = @recorder.events.find { |e| e.kind == :pending_decision && e.title.include?("Children of Memory") }
    assert conflict, "expected an ISFDB pending_decision notification for Children of Memory"
    assert_match(/enrichment_field_conflict/, conflict.title)
    assert_equal "Children of Memory", conflict.fields["title"]
    assert_equal "2022 → 2019", conflict.fields["publish_date"]
  end

  test "notifies pending_decision for a reread_conflict raised during the run" do
    work = Work.create!(title: "Neuromancer", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work: work, edition: edition)
    EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")
    Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2010, 5, 1))

    # The real Neuromancer read-shelf fixture item, replayed against
    # currently-reading — exactly the real scenario a reread_conflict
    # models (a completed Reading, no open one, currently-reading fires).
    parser = Goodreads::RssClient.allocate
    items = parser.send(:parse, File.read(Rails.root.join("test/fixtures/files/goodreads_read_sample.xml")))
    neuromancer_item = items.find { |i| i.goodreads_book_id == "953070" }

    stub_client = Object.new
    stub_client.define_singleton_method(:fetch) do |shelf|
      shelf == "currently-reading" ? [ neuromancer_item ] : []
    end

    GoodreadsSyncJob.perform_now(rss_client: stub_client)

    pending = @recorder.events.select { |e| e.kind == :pending_decision }
    assert_equal 1, pending.size
    assert_match(/reread_conflict/, pending.first.title)
  end

  test "always sends exactly one sync_summary notification per run" do
    GoodreadsSyncJob.perform_now(rss_client: FixtureRssClient.new)

    summaries = @recorder.events.select { |e| e.kind == :sync_summary }
    assert_equal 1, summaries.size
  end

  test "notifies sync_error and re-raises when the sync itself blows up" do
    assert_raises(RuntimeError) { GoodreadsSyncJob.perform_now(rss_client: RaisingRssClient.new) }

    errors = @recorder.events.select { |e| e.kind == :sync_error }
    assert_equal 1, errors.size
  end
end

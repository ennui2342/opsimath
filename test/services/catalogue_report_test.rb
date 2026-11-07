require "test_helper"

class CatalogueReportTest < ActiveSupport::TestCase
  class Capture
    attr_reader :events

    def initialize = @events = []
    def notify(event) = @events << event
  end

  setup do
    @capture = Capture.new
    Notifications.notifiers = [ @capture ]
    @work = Work.create!(title: "The Birthgrave", literary_form: "novel")
  end

  teardown { Notifications.notifiers = nil }

  test "edits are posted once, after they've settled, to #catalogue" do
    CatalogueEvent.create!(origin: "web", kind: "added", work: @work, summary: "Added The Birthgrave: Orbit 1979, owned", created_at: 5.minutes.ago)
    fresh = CatalogueEvent.create!(origin: "web", kind: "status", summary: "Kraken (Pan 2011): owned → sold", created_at: 30.seconds.ago)
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", summary: "x found in ISFDB", created_at: 5.minutes.ago)

    assert_equal 1, CatalogueReport.post_edits
    event = @capture.events.sole
    assert_equal [ :catalogue, "Catalogue: 1 change" ], [ event.channel, event.title ]
    assert_equal "• Added The Birthgrave: Orbit 1979, owned", event.description
    assert_nil fresh.reload.reported_at # still settling

    assert_equal 0, CatalogueReport.post_edits(now: 30.seconds.ago) # nothing new and settled
  end

  test "the morning digest: links and new printings counted, wanted books first, other jobs in a line each" do
    want_work = Work.create!(title: "Brasyl", literary_form: "novel")
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", work: @work, summary: "The Birthgrave found in ISFDB", details: { provider: "isfdb", wanted: false })
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", work: want_work, summary: "Brasyl found in Open Library", details: { provider: "openlibrary", wanted: true })
    CatalogueEvent.create!(origin: "known_editions", kind: "new_printings", work: @work, summary: "The Birthgrave: 2 new printings in ISFDB (DAW 2024)", details: { count: 2, wanted: false })
    CatalogueEvent.create!(origin: "known_editions", kind: "new_printings", work: want_work, summary: "Brasyl: 1 new printing in ISFDB (Gollancz 2025)", details: { count: 1, wanted: true })
    CatalogueEvent.create!(origin: "sweep", kind: "decisions_closed", summary: "Closed 3 review decisions with nothing left to decide")

    assert_equal 5, CatalogueReport.post_digest

    lines = @capture.events.sole.description.split("\n")
    assert_equal "**Books found by providers:** 1 in ISFDB, 1 in Open Library", lines[0]
    assert_equal "• ★ Brasyl found in Open Library (wanted)", lines[1]
    assert_equal "**New printings:** 3 across 2 books", lines[2]
    assert_equal "• ★ Brasyl: 1 new printing in ISFDB (Gollancz 2025)", lines[3]
    assert_includes lines, "**Review queue:** Closed 3 review decisions with nothing left to decide"
    assert_equal 0, CatalogueReport.post_digest
  end

  test "a #catalogue post never lands in the default channel when #catalogue isn't configured" do
    notifier = Notifications::DiscordNotifier.new(bot_token: "t", channel_id: "default", channels: { catalogue: nil })

    assert_nil notifier.notify(Notifications::Event.new(kind: :catalogue, level: :info, title: "x", channel: :catalogue))
  end
end

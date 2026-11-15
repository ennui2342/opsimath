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

  def titles(event) = event.embeds.map { |e| e[:title] }

  test "Mark's edits and hand-run corrections are posted once they've settled, each in its own section" do
    CatalogueEvent.create!(origin: "web", kind: "added", work: @work, summary: "Added The Birthgrave: Orbit 1979, owned", created_at: 5.minutes.ago)
    CatalogueEvent.create!(origin: "job", kind: "relinked", summary: "Zoo City: anchored to the novel's printing", details: { by: "correction" }, created_at: 5.minutes.ago)
    fresh = CatalogueEvent.create!(origin: "web", kind: "status", summary: "Kraken (Pan 2011): owned → sold", created_at: 30.seconds.ago)
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", summary: "x found in ISFDB", created_at: 5.minutes.ago)

    assert_equal 2, CatalogueReport.post_edits
    event = @capture.events.sole
    assert_equal [ :catalogue, "Catalogue: 2 changes" ], [ event.channel, event.title ]
    assert_equal [ "Your changes — 1", "Corrections (run by hand) — 1" ], titles(event)
    assert_equal "• Added The Birthgrave: Orbit 1979, owned", event.embeds.first[:description]
    assert_nil fresh.reload.reported_at # still settling
    assert_equal 0, CatalogueReport.post_edits(now: 30.seconds.ago)
  end

  test "the morning digest: works, editions and housekeeping in their own sections; wishlist books first; corrections aren't in it" do
    want_work = Work.create!(title: "Brasyl", literary_form: "novel")
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", work: @work, summary: "The Birthgrave found in ISFDB", details: { provider: "isfdb" })
    CatalogueEvent.create!(origin: "known_editions", kind: "linked", work: want_work, summary: "Brasyl found in Open Library", details: { provider: "openlibrary", wanted: true })
    CatalogueEvent.create!(origin: "title_cleanup", kind: "retitled", work: @work, summary: "Work retitled: “A” → ISFDB's “B”")
    CatalogueEvent.create!(origin: "anchored_refresh", kind: "refreshed", work: @work, summary: "The Birthgrave: publish date from ISFDB")
    CatalogueEvent.create!(origin: "known_editions", kind: "new_printings", work: @work, summary: "The Birthgrave: 2 new editions known in ISFDB (DAW 2024)", details: { count: 2 })
    CatalogueEvent.create!(origin: "sweep", kind: "decisions_closed", summary: "Closed 3 review decisions with nothing left to decide")
    CatalogueEvent.create!(origin: "job", kind: "relinked", summary: "a correction", details: { by: "correction" })

    assert_equal 6, CatalogueReport.post_digest

    event = @capture.events.sole
    assert_equal [ "Works found in ISFDB or Open Library — 2", "Works retitled — 1", "Your editions updated — 1", "New editions known — 1", "Housekeeping — 1" ],
                 titles(event)
    assert_equal "• ★ Brasyl found in Open Library (on your wishlist)", event.embeds.first[:description].lines.first.chomp
    assert_equal "• Review queue: Closed 3 review decisions with nothing left to decide", event.embeds.last[:description]
    assert_equal 0, CatalogueReport.post_digest
  end

  test "nothing is cut off: a long section continues in further embeds, numbered" do
    lines = 120.times.map { |n| "Book #{n} with quite a long title to fill the embed up: in Saga ##{n}" }

    embeds = CatalogueReport.embeds([ CatalogueReport::Section.new("Works' series", 1, lines) ])

    assert_operator embeds.size, :>, 1
    assert_equal "Works' series — 120 (1 of #{embeds.size})", embeds.first[:title]
    assert embeds.all? { |e| e[:description].size <= CatalogueReport::DESCRIPTION_CHARS }
    assert_equal 120, embeds.sum { |e| e[:description].lines.size }
  end

  test "a #catalogue post never lands in the default channel when #catalogue isn't configured" do
    notifier = Notifications::DiscordNotifier.new(bot_token: "t", channel_id: "default", channels: { catalogue: nil })

    assert_nil notifier.notify(Notifications::Event.new(kind: :catalogue, level: :info, title: "x", channel: :catalogue))
  end

  test "a change made outside a job and off the web — run by hand — is a correction" do
    assert_not CatalogueEvent.correction? # a test isn't a runner
    Current.set(job: true) { assert_not CatalogueEvent.correction? }
  end
end

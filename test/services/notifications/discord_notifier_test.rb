require "test_helper"

module Notifications
  class DiscordNotifierTest < ActiveSupport::TestCase
    WEBHOOK = "https://discord.com/api/webhooks/999/secret-token".freeze

    test "posts a Discord embed to the incoming webhook, with no bot Authorization header" do
      stub = stub_request(:post, WEBHOOK)
        .with(headers: { "Content-Type" => "application/json" }) do |request|
          embed = JSON.parse(request.body)["embeds"].first
          !request.headers.key?("Authorization") &&
            embed["title"] == "Needs review: reread_conflict — Neuromancer" &&
            embed["color"] == 0xFAA61A &&
            embed["fields"].include?({ "name" => "shelf", "value" => "currently-reading", "inline" => true })
        end.to_return(status: 204)

      notifier = DiscordNotifier.new(webhook_url: WEBHOOK)
      event = Event.new(kind: :pending_decision, level: :warn, title: "Needs review: reread_conflict — Neuromancer",
                         fields: { "shelf" => "currently-reading" })

      notifier.notify(event)

      assert_requested stub
    end

    test "a digest event carries its description and title link; fields-only events leave them out" do
      stub = stub_request(:post, WEBHOOK).with do |request|
        embed = JSON.parse(request.body)["embeds"].first
        embed["url"] == "https://opsimath.test/finds" && embed["description"] == "★ **Brasyl** — £3.52" && embed["fields"] == []
      end.to_return(status: 204)
      plain = stub_request(:post, WEBHOOK).with do |request|
        embed = JSON.parse(request.body)["embeds"].first
        !embed.key?("url") && !embed.key?("description")
      end.to_return(status: 204)

      notifier = DiscordNotifier.new(webhook_url: WEBHOOK)
      notifier.notify(Event.new(kind: :ebay_finds, level: :info, title: "eBay: 1 new find", fields: {},
                                description: "★ **Brasyl** — £3.52", url: "https://opsimath.test/finds"))
      notifier.notify(Event.new(kind: :sync_summary, level: :info, title: "x", fields: { "a" => "b" }))

      assert_requested stub
      assert_requested plain
    end

    test "raises ServiceError on a non-2xx response, without the webhook URL in the message" do
      stub_request(:post, WEBHOOK).to_return(status: 401, body: "unauthorized")

      error = assert_raises(DiscordNotifier::ServiceError) do
        DiscordNotifier.new(webhook_url: WEBHOOK).notify(Event.new(kind: :sync_summary, level: :info, title: "x", fields: {}))
      end
      assert_not_includes error.message, "secret-token"
    end

    test "posts nothing when no webhook is configured" do
      assert_nil DiscordNotifier.new(webhook_url: nil).notify(Event.new(kind: :sync_summary, level: :info, title: "x", fields: {}))
      assert_not_requested :post, /discord/
    end

    test "a report in sections goes out as embeds, in as many messages as Discord's limits need" do
      bodies = []
      stub_request(:post, WEBHOOK).to_return do |request|
        bodies << JSON.parse(request.body)
        { status: 204 }
      end
      embeds = 12.times.map { |n| { title: "Section #{n}", description: "x" * 900, color: 1 } }

      DiscordNotifier.new(webhook_url: WEBHOOK).notify(Event.new(kind: :catalogue, level: :info, title: "Catalogue", embeds:))

      assert_operator bodies.size, :>, 1
      assert_equal 12, bodies.sum { |b| b["embeds"].size }
      assert bodies.all? { |b| b["embeds"].size <= 10 && b["embeds"].sum { |e| e["description"].size + e["title"].size } <= 6000 }
    end
  end
end

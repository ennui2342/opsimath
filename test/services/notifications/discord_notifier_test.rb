require "test_helper"

module Notifications
  class DiscordNotifierTest < ActiveSupport::TestCase
    test "posts a Discord embed via the bot channel-messages endpoint" do
      stub = stub_request(:post, "https://discord.com/api/v10/channels/999/messages")
        .with(
          headers: { "Authorization" => "Bot test-token", "Content-Type" => "application/json" }
        ) do |request|
          body = JSON.parse(request.body)
          embed = body["embeds"].first
          embed["title"] == "Needs review: reread_conflict — Neuromancer" &&
            embed["color"] == 0xFAA61A &&
            embed["fields"].include?({ "name" => "shelf", "value" => "currently-reading", "inline" => true })
        end.to_return(status: 200, body: "{}")

      notifier = DiscordNotifier.new(bot_token: "test-token", channel_id: "999")
      event = Event.new(kind: :pending_decision, level: :warn, title: "Needs review: reread_conflict — Neuromancer",
                         fields: { "shelf" => "currently-reading" })

      notifier.notify(event)

      assert_requested stub
    end

    test "raises ServiceError on a non-2xx response, so Dispatcher can rescue and log it" do
      stub_request(:post, "https://discord.com/api/v10/channels/999/messages").to_return(status: 401, body: "unauthorized")

      notifier = DiscordNotifier.new(bot_token: "bad-token", channel_id: "999")
      event = Event.new(kind: :sync_summary, level: :info, title: "x", fields: {})

      assert_raises(DiscordNotifier::ServiceError) { notifier.notify(event) }
    end
  end
end

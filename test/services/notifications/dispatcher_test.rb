require "test_helper"

module Notifications
  class DispatcherTest < ActiveSupport::TestCase
    class RecordingNotifier
      attr_reader :events

      def initialize
        @events = []
      end

      def notify(event)
        @events << event
      end
    end

    class FailingNotifier
      def notify(_event)
        raise "boom"
      end
    end

    teardown do
      Notifications.notifiers = nil
    end

    test "dispatches the event to every configured notifier" do
      recorder = RecordingNotifier.new
      Notifications.notifiers = [ recorder ]
      event = Event.new(kind: :sync_summary, level: :info, title: "test", fields: {})

      Notifications.notify(event)

      assert_equal [ event ], recorder.events
    end

    test "one notifier failing doesn't stop the others, or raise out of .notify" do
      recorder = RecordingNotifier.new
      Notifications.notifiers = [ FailingNotifier.new, recorder ]
      event = Event.new(kind: :sync_summary, level: :info, title: "test", fields: {})

      assert_nothing_raised { Notifications.notify(event) }

      assert_equal [ event ], recorder.events
    end

    test "LogNotifier is always in the default list; DiscordNotifier joins iff DISCORD_WEBHOOK is set" do
      original = ENV["DISCORD_WEBHOOK"]

      ENV["DISCORD_WEBHOOK"] = "https://discord.test/api/webhooks/1/t"
      assert_equal [ LogNotifier, DiscordNotifier ], Notifications.default_notifiers.map(&:class)

      ENV.delete("DISCORD_WEBHOOK")
      assert_equal [ LogNotifier ], Notifications.default_notifiers.map(&:class)
    ensure
      ENV["DISCORD_WEBHOOK"] = original
    end
  end
end

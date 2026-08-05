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

    test "LogNotifier is always in the default list; DiscordNotifier joins iff a bot_token credential is present" do
      classes = Notifications.default_notifiers.map(&:class)

      assert_includes classes, LogNotifier
      # Tests the conditional itself, not a specific environment's real
      # credential state — CI has no RAILS_MASTER_KEY at all, so this
      # must hold either way, not assume a bot_token is configured.
      if Rails.application.credentials.dig(:discord, :bot_token).present?
        assert_includes classes, DiscordNotifier
      else
        assert_not_includes classes, DiscordNotifier
      end
    end
  end
end

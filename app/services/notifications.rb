module Notifications
  # The one thing a caller (a job, a service) actually calls —
  # `Notifications.notify(event)`. Which backends are active is decided
  # here, not by the caller; adding a new backend later means adding one
  # more class to `default_notifiers`, not touching any call site.
  def self.notify(event)
    notifiers.each do |notifier|
      notifier.notify(event)
    rescue StandardError => e
      # A notification failure must never break the job that triggered
      # it — the sync/enrichment work already happened; losing sight of
      # it isn't worth failing the whole run over.
      Rails.logger.error("[Notifications] #{notifier.class} failed: #{e.class}: #{e.message}")
    end
  end

  # Overridable for tests (no mocking gem is set up in this project) —
  # `Notifications.notifiers = [...]` swaps the active list;
  # `Notifications.notifiers = nil` restores the real credential-driven
  # default.
  def self.notifiers=(list)
    @notifiers = list
  end

  def self.notifiers
    @notifiers || default_notifiers
  end

  def self.default_notifiers
    list = [ LogNotifier.new ]
    list << DiscordNotifier.new if Rails.application.credentials.dig(:discord, :bot_token).present?
    list
  end
end

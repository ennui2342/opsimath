module Notifications
  # The zero-config default — always active, needs no credentials. Real
  # backends (Discord, ...) are additive on top of this, never a
  # replacement for it.
  class LogNotifier
    def notify(event)
      Rails.logger.info("[notify:#{event.level}] #{event.title} #{event.fields}")
    end
  end
end

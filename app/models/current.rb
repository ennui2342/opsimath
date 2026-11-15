class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_token
  # Set while a background job runs (ApplicationJob): a catalogue change
  # made outside one, and not by Mark on the web, is a correction run by
  # hand (CatalogueEvent).
  attribute :job
  delegate :user, to: :session, allow_nil: true
end

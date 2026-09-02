class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_token
  delegate :user, to: :session, allow_nil: true
end

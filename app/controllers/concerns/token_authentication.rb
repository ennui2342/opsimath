# Bearer-token auth for machine endpoints (the mobile snapshot today),
# separate from the human session gate in Authentication. Reads
# `Authorization: Bearer <token>` and checks it against ApiToken — see
# docs/PHILOSOPHY.md principle 19.
module TokenAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_api_token
  end

  private

  def require_api_token
    authenticate_or_request_with_http_token do |token, _options|
      Current.api_token = ApiToken.authenticate(token)
    end
  end
end

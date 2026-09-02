module Mobile
  # Serves the offline shop-lookup PWA shell (docs/MOBILE.md step 6). The
  # page itself is behind the normal session gate; it hands the client a
  # fresh ApiToken and the snapshot URLs, which the PWA persists and then
  # uses to sync in the background. The manifest and service worker are
  # open (a logged-out re-fetch of the SW must not 302 to login).
  class AppController < ApplicationController
    allow_unauthenticated_access only: %i[manifest service_worker]
    # The manifest and SW carry nothing user-specific and are loaded from
    # non-fetch contexts (a <link rel=manifest>, SW registration), which
    # trips Rails' cross-origin-JavaScript guard.
    skip_forgery_protection only: %i[manifest service_worker]

    layout false

    SCOPE = "/mobile"
    TOKEN_NAME = "mobile-pwa"

    def show
      @config = {
        apiToken: pwa_token, # nil once the client already has one — don't rotate it away
        resetUrl: mobile_app_path(reset: 1),
        versionUrl: mobile_snapshot_version_path,
        snapshotUrl: mobile_snapshot_path,
        sqljsWasmUrl: helpers.asset_path("sqljs.wasm"),
        serviceWorkerUrl: mobile_service_worker_path,
        scope: SCOPE
      }
    end

    def manifest
      render :manifest, content_type: "application/manifest+json"
    end

    def service_worker
      expires_now
      # Lets a SW served from /mobile/service-worker control the whole /mobile prefix.
      response.set_header("Service-Worker-Allowed", SCOPE)
      render :service_worker, content_type: "text/javascript"
    end

    private

    # Issue a token only when there isn't one to reuse, or on an explicit
    # ?reset — ApiToken reveals its raw value only at issue, so rotating on
    # every load would strand a client that already stored one. The client
    # persists what it's given and keeps using it.
    def pwa_token
      existing = Current.user.api_tokens.find_by(name: TOKEN_NAME)
      return nil if existing && !params[:reset]

      existing&.destroy
      _token, raw = ApiToken.issue!(user: Current.user, name: TOKEN_NAME)
      raw
    end
  end
end

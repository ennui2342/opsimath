require "active_support/core_ext/integer/time"

# ActionDispatch::AssumeSSL (config.assume_ssl) marks *every* request as SSL regardless of
# host, which makes ActionDispatch::SSL's request.ssl? always true and its `ssl_options`
# redirect `exclude` (below) unreachable dead code. This does the same unconditional
# "assume the reverse proxy terminated TLS" job, except it skips the assumption for
# opsimath.k8s.ecafe.org, which genuinely has no TLS anywhere in its path.
class AssumeSSLExceptHost
  def initialize(app, excluded_host)
    @app = app
    @excluded_host = excluded_host
  end

  def call(env)
    if env["HTTP_HOST"].to_s.split(":").first != @excluded_host
      env["HTTPS"] = "on"
      env["rack.url_scheme"] = "https"
      env["HTTP_X_FORWARDED_PORT"] = "443"
      env["HTTP_X_FORWARDED_PROTO"] = "https"
    end
    @app.call(env)
  end
end

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy,
  # except for opsimath.k8s.ecafe.org (see AssumeSSLExceptHost above).
  config.assume_ssl = false
  config.middleware.insert_before ActionDispatch::SSL, AssumeSSLExceptHost, "opsimath.k8s.ecafe.org"

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # opsimath.k8s.ecafe.org has no TLS cert (internal-DNS-only, plain HTTP ingress) - forcing
  # https there redirects into Traefik's self-signed fallback cert. Tailscale ingress
  # (opsimath.tail611131.ts.net) has a real cert and keeps the redirect/HSTS/secure-cookie
  # behavior as normal.
  config.ssl_options = { redirect: { exclude: ->(request) { request.host == "opsimath.k8s.ecafe.org" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

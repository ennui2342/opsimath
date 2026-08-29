require "active_support/core_ext/integer/time"

# UAT / pre-production. A faithful clone of config/environments/production.rb
# — eager loading, no code reloading, caching on, real (non-verbose) error
# pages — so `bin/uat` catches the class of problem dev mode hides
# (eager-load failures, asset build issues, cache behaviour). The only
# things relaxed are the ones that assume a TLS-terminating reverse proxy
# in front: this stack is plain HTTP on localhost:3001.
Rails.application.configure do
  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled — same as production. Flip to true (or
  # read `docker compose -f docker-compose.uat.yml logs -f web`) when
  # debugging a UAT failure.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Store uploaded files on the local file system (see config/storage.yml).
  # bin/uat-db-pull rsyncs the real production blobs into the uat_storage volume.
  config.active_storage.service = :local

  # No reverse proxy here — the stack is plain HTTP on localhost. This is
  # the one meaningful departure from production.rb, which assumes TLS
  # termination upstream and forces HTTPS.
  config.assume_ssl = false
  config.force_ssl = false

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Same queuing backend as production.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 3001 }

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections, as in production.
  config.active_record.attributes_for_inspect = [ :id ]
end

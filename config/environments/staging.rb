require "active_support/core_ext/integer/time"

# Staging environment — mirrors production behavior with debug-friendly logging
# Uses staging database via DATABASE_URL

Rails.application.configure do
  config.enable_reloading = false

  # TODO: Fix Zeitwerk autoloading then enable eager_load
  config.eager_load = false

  config.consider_all_requests_local = false

  # Read secret_key_base from environment variable
  config.secret_key_base = ENV["SECRET_KEY_BASE"]

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # SSL terminated by Nginx/reverse proxy
  config.assume_ssl = true
  config.force_ssl = true

  # Verbose logging for staging debugging
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Report deprecations in staging so we catch them early.
  config.active_support.report_deprecations = true

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.i18n.fallbacks = true

  # Use memory cache for staging (Solid Cache has CockroachDB compatibility issues)
  config.cache_store = :memory_store

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections.
  config.active_record.attributes_for_inspect = [ :id ]

  # Disable host authorization for staging (behind reverse proxy)
  config.hosts.clear if config.hosts.respond_to?(:clear)
  config.host_authorization = false
  config.require_master_key = false
end

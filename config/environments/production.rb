require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = true

  config.consider_all_requests_local = false

  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "r2").to_sym

  config.assume_ssl = true

  config.force_ssl = true

  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  config.log_tags  = [ :request_id ]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.rails_semantic_logger.format = :json

  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  config.cache_store = :solid_cache_store

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.default_url_options = { host: "example.com" }

  config.i18n.fallbacks = true

  config.active_record.dump_schema_after_migration = false

  config.active_record.attributes_for_inspect = [ :id ]

  # AllowedHosts fails boot on a blank value, which Rails would read as allow everything.
  require Rails.root.join("lib/allowed_hosts")
  config.hosts = AllowedHosts.parse!(ENV.fetch("ALLOWED_HOSTS"))

  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Rejects traffic that did not come through Cloudflare when CLOUDFLARE_ONLY is set.
  require Rails.root.join("app/middleware/cloudflare_only")
  config.middleware.insert_before Rack::Runtime, CloudflareOnly

  # Enforces subdomain routing when SUBDOMAIN_ROUTING=strict. After CloudflareOnly so IP filtering runs first.
  require Rails.root.join("app/middleware/subdomain_router")
  config.middleware.insert_before Rack::Runtime, SubdomainRouter
end

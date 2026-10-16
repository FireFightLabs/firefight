Rails.application.configure do
  # Fixtures for encrypted attributes are written encrypted, as the app would store them.
  config.active_record.encryption.encrypt_fixtures = true
  config.enable_reloading = false

  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.action_dispatch.show_exceptions = :rescuable

  config.action_controller.allow_forgery_protection = false

  config.active_storage.service = :test

  config.action_mailer.delivery_method = :test

  config.action_mailer.default_url_options = { host: "example.com" }
  config.x.mail_configured = true

  config.active_support.deprecation = :stderr

  config.action_controller.raise_on_missing_callback_actions = true

  config.active_job.queue_adapter = :test

  # Model.connection keeps a database connection until the job ends, so a fiber waiting on a model would hold one and
  # the pool sized for fiber workers would run dry. with_connection gives it back after the query.
  config.active_record.permanent_connection_checkout = :disallowed
end

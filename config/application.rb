require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

# Sentry loads only where a deployment sets SENTRY_DSN. Its Railtie has to be in place before the app initializes to
# add its middleware and hook into Active Job, and config/initializers/sentry.rb starts it.
require_relative "../lib/error_reporting"
if ErrorReporting.dsn
  require "sentry-ruby"
  require "sentry-rails"
end

module Firefight
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks omniauth slack])

    config.session_store :cookie_store, key: "_firefight_session", expire_after: 12.hours, same_site: :lax

    # Lets a model's locale say an attribute's errors are whole sentences, such as a runbook's watch naming the item at fault.
    config.active_model.i18n_customize_full_message = true

    # Rails renders its own debug pages where they apply, this covers the rest.
    config.exceptions_app = routes

    # A deploy stops a worker with TERM. It takes no new jobs and gives the ones it holds this long to finish, which covers
    # every short job. Longer work is handed back and resumes (docs/architecture.md, Deploys). The platform's grace period
    # must be longer than this, or the worker is killed before it hands anything back.
    config.solid_queue.shutdown_timeout = 25.seconds

    # The workers that mostly wait run each job as a fiber (config/queue.yml), and Solid Queue refuses to start them unless
    # Current, the database connection and the rest of Rails' per request state belong to a fiber rather than a thread. It
    # holds for every process, Puma included, where each request still runs on a fiber of its own thread.
    config.active_support.isolation_level = :fiber

    # Faylee bug reports, off unless a deployment sets both. A blank value counts as unset.
    config.x.faylee_verification_token = ENV["FAYLEE_VERIFICATION_TOKEN"].presence
    config.x.faylee_site_id = ENV["FAYLEE_SITE_ID"].presence
  end
end

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Firefight
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks omniauth slack])

    config.session_store :cookie_store, key: "_firefight_session", expire_after: 12.hours, same_site: :lax

    # Rails renders its own debug pages where they apply, this covers the rest.
    config.exceptions_app = routes
  end
end

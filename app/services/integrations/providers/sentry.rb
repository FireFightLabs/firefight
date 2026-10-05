module Integrations
  module Providers
    Sentry = Provider.new(key: "sentry", adapter: "Integrations::Capabilities::Sentry")
  end
end

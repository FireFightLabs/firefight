module Integrations
  module Providers
    Honeybadger = Provider.new(
      key: "honeybadger", adapter: "Integrations::Capabilities::Honeybadger", health_probe: "Integrations::HealthProbes::Honeybadger",
      redacted_fields: %w[token]
    )
  end
end

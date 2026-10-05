module Integrations
  module Providers
    Honeycomb = Provider.new(
      key: "honeycomb", adapter: "Integrations::Capabilities::Honeycomb", health_probe: "Integrations::HealthProbes::Honeycomb"
    )
  end
end

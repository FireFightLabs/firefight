module Integrations
  module Providers
    Betterstack = Provider.new(
      key: "betterstack", adapter: "Integrations::Capabilities::Betterstack", health_probe: "Integrations::HealthProbes::Betterstack"
    )
  end
end

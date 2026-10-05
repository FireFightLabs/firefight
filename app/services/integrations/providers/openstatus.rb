module Integrations
  module Providers
    Openstatus = Provider.new(
      key: "openstatus", adapter: "Integrations::Capabilities::Openstatus", health_probe: "Integrations::HealthProbes::Openstatus",
      source_links: "Integrations::SourceLinks::Openstatus"
    )
  end
end

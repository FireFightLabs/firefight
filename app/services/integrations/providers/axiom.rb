module Integrations
  module Providers
    Axiom = Provider.new(
      key: "axiom", adapter: "Integrations::Capabilities::Axiom", health_probe: "Integrations::HealthProbes::Axiom",
      source_links: "Integrations::SourceLinks::Axiom"
    )
  end
end

module Integrations
  module Providers
    Logfire = Provider.new(
      key: "logfire", adapter: "Integrations::Capabilities::Logfire", health_probe: "Integrations::HealthProbes::Logfire",
      baseline_reader: "Integrations::BaselineReaders::Logfire", source_links: "Integrations::SourceLinks::Logfire"
    )
  end
end

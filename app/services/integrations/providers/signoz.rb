module Integrations
  module Providers
    Signoz = Provider.new(
      key: "signoz", adapter: "Integrations::Capabilities::Signoz", health_probe: "Integrations::HealthProbes::Signoz",
      baseline_reader: "Integrations::BaselineReaders::Signoz", source_links: "Integrations::SourceLinks::Signoz",
      error_reader: "Integrations::ErrorReaders::Signoz"
    )
  end
end

module Integrations
  module Providers
    Grafana = Provider.new(
      key: "grafana",
      adapter: "Integrations::Capabilities::Grafana",
      baseline_reader: "Integrations::BaselineReaders::Grafana",
      health_probe: "Integrations::HealthProbes::Grafana",
      source_links: "Integrations::SourceLinks::Grafana",
      error_reader: "Integrations::ErrorReaders::Grafana"
    )
  end
end

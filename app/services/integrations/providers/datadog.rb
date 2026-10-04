module Integrations
  module Providers
    Datadog = Provider.new(key: "datadog", adapter: "Integrations::Capabilities::Datadog", source_links: "Integrations::SourceLinks::Datadog")
  end
end

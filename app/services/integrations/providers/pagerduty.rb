module Integrations
  module Providers
    Pagerduty = Provider.new(key: "pagerduty", source_links: "Integrations::SourceLinks::Pagerduty", error_reader: "Integrations::ErrorReaders::Pagerduty")
  end
end

module Integrations
  module Providers
    Newrelic = Provider.new(key: "newrelic", adapter: "Integrations::Capabilities::Newrelic",
                            baseline_reader: "Integrations::BaselineReaders::Newrelic", source_links: "Integrations::SourceLinks::Newrelic")
  end
end

module Integrations
  module Providers
    # A service integration's key sends events that page people, so it is a credential.
    Pagerduty = Provider.new(key: "pagerduty", source_links: "Integrations::SourceLinks::Pagerduty", error_reader: "Integrations::ErrorReaders::Pagerduty",
                             redacted_fields: %w[integration_key])
  end
end

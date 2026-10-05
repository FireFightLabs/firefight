module Integrations
  module Providers
    Posthog = Provider.new(key: "posthog", adapter: "Integrations::Capabilities::Posthog", source_links: "Integrations::SourceLinks::Posthog")
  end
end

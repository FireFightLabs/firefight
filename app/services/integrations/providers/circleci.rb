module Integrations
  module Providers
    Circleci = Provider.new(key: "circleci", adapter: "Integrations::Capabilities::Circleci", source_links: "Integrations::SourceLinks::Circleci")
  end
end

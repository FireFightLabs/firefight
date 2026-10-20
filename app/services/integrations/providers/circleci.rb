module Integrations
  module Providers
    Circleci = Provider.new(
      key: "circleci",
      pack: "Integrations::Packs::Circleci",
      adapter: "Integrations::Capabilities::Circleci",
      map_events: "Integrations::MapEventSources::Circleci",
      read_guard: "Integrations::ReadGuards::Circleci",
      # A connection through CircleCI's hosted MCP server links its run lists to the project's pipelines page.
      source_links: "Integrations::SourceLinks::Circleci"
    )
  end
end

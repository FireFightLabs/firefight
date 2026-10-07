module Integrations
  module Providers
    Github = Provider.new(
      key: "github",
      pack: "Integrations::Packs::Github",
      adapter: "Integrations::Capabilities::Github",
      map_events: "Integrations::MapEventSources::Github",
      issue_tracker: "Integrations::IssueTrackers::Github"
    )
  end
end

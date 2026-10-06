module Integrations
  module Providers
    Gitlab = Provider.new(
      key: "gitlab",
      pack: "Integrations::Packs::Gitlab",
      adapter: "Integrations::Capabilities::Gitlab",
      map_events: "Integrations::MapEventSources::Gitlab"
    )
  end
end

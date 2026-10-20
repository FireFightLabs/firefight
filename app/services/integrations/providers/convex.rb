module Integrations
  module Providers
    Convex = Provider.new(
      key: "convex",
      pack: "Integrations::Packs::Convex",
      adapter: "Integrations::Capabilities::Convex",
      map_events: "Integrations::MapEventSources::Convex",
      mitigation_reader: "Integrations::MitigationReaders::Convex"
    )
  end
end

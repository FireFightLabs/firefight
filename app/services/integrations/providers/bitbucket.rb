module Integrations
  module Providers
    Bitbucket = Provider.new(
      key: "bitbucket",
      pack: "Integrations::Packs::Bitbucket",
      adapter: "Integrations::Capabilities::Bitbucket",
      map_events: "Integrations::MapEventSources::Bitbucket"
    )
  end
end

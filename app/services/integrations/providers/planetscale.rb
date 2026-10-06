module Integrations
  module Providers
    # A database's and a branch's state as PlanetScale's API documents them.
    Planetscale = Provider.new(
      key: "planetscale", adapter: "Integrations::Capabilities::Planetscale", map_reader: "Integrations::MapReaders::Planetscale",
      source_links: "Integrations::SourceLinks::Planetscale", map_events: "Integrations::MapEventSources::Planetscale",
      status_words: { "importing" => "pending", "import_ready" => "ready", "sleep_in_progress" => "pending", "awakening" => "starting" }
    )
  end
end

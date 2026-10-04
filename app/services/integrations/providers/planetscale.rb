module Integrations
  module Providers
    Planetscale = Provider.new(
      key: "planetscale", adapter: "Integrations::Capabilities::Planetscale", map_reader: "Integrations::MapReaders::Planetscale",
      source_links: "Integrations::SourceLinks::Planetscale"
    )
  end
end

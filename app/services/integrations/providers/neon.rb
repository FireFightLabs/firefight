module Integrations
  module Providers
    Neon = Provider.new(
      key: "neon", adapter: "Integrations::Capabilities::Neon", map_reader: "Integrations::MapReaders::Neon",
      source_links: "Integrations::SourceLinks::Neon"
    )
  end
end

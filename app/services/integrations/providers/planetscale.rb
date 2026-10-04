module Integrations
  module Providers
    Planetscale = Provider.new(
      key: "planetscale", map_reader: "Integrations::MapReaders::Planetscale", source_links: "Integrations::SourceLinks::Planetscale"
    )
  end
end

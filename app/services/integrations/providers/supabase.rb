module Integrations
  module Providers
    Supabase = Provider.new(
      key: "supabase", adapter: "Integrations::Capabilities::Supabase", map_reader: "Integrations::MapReaders::Supabase",
      source_links: "Integrations::SourceLinks::Supabase"
    )
  end
end

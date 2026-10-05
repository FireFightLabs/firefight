module Integrations
  module Providers
    Cloudflare = Provider.new(
      key: "cloudflare",
      adapter: "Integrations::Capabilities::Cloudflare",
      map_reader: "Integrations::MapReaders::Cloudflare",
      source_links: "Integrations::SourceLinks::Cloudflare",
      read_guard: "Integrations::ReadGuards::Cloudflare"
    )
  end
end

module Integrations
  module Providers
    # status_words: a zone's in-between states and a Tunnel's inactive, as Cloudflare's API writes them, and the disabled
    # MapReaders::Cloudflare gives a load balancer or pool that is switched off.
    Cloudflare = Provider.new(
      key: "cloudflare",
      adapter: "Integrations::Capabilities::Cloudflare",
      map_reader: "Integrations::MapReaders::Cloudflare",
      map_events: "Integrations::MapEventSources::Cloudflare",
      source_links: "Integrations::SourceLinks::Cloudflare",
      read_guard: "Integrations::ReadGuards::Cloudflare",
      error_reader: "Integrations::ErrorReaders::Cloudflare",
      status_words: { "initializing" => "pending", "moved" => "unavailable", "inactive" => "stopped", "disabled" => "stopped" }
    )
  end
end

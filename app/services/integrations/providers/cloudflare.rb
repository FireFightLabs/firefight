module Integrations
  module Providers
    # redacted_fields are the answer fields Cloudflare's API schema gives a secret in, such as a Turnstile widget's secret,
    # an Access app's client secret and a Logpush job's destination, which can carry a storage key. A tunnel's token is
    # base64 of JSON starting with its account, which no shape in Chat::SecretFree matches. A read whose whole answer is
    # a secret is refused by the read guard (ReadGuards::Cloudflare.withheld).
    # status_words: a zone's in-between states and a Tunnel's inactive, as Cloudflare's API writes them, and the disabled
    # MapReaders::Cloudflare gives a load balancer or pool that is switched off.
    Cloudflare = Provider.new(
      key: "cloudflare",
      adapter: "Integrations::Capabilities::Cloudflare",
      map_reader: "Integrations::MapReaders::Cloudflare",
      map_events: "Integrations::MapEventSources::Cloudflare",
      source_links: "Integrations::SourceLinks::Cloudflare",
      read_guard: "Integrations::ReadGuards::Cloudflare",
      mitigation_reader: "Integrations::MitigationReaders::Cloudflare",
      error_reader: "Integrations::ErrorReaders::Cloudflare",
      redacted_fields: %w[
        secret client_secret password passphrase private_key privkey custom_key streamKey stream_key license_key jwt destination_conf headers
      ],
      redacted_patterns: { "cloudflare_tunnel_token" => %r{\beyJhIjoi[A-Za-z0-9+/]{20,}={0,2}} },
      status_words: { "initializing" => "pending", "moved" => "unavailable", "inactive" => "stopped", "disabled" => "stopped" }
    )
  end
end

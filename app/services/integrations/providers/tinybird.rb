module Integrations
  module Providers
    # A Tinybird token is p. then one base64 payload and a signature, which the two part JWT shape does not catch, and
    # endpoints are often called with it in the address, so it is replaced wherever an answer carries it.
    Tinybird = Provider.new(
      key: "tinybird", pack: "Integrations::Packs::Tinybird", adapter: "Integrations::Capabilities::Tinybird",
      read_guard: "Integrations::ReadGuards::Tinybird",
      redacted_patterns: { "tinybird_token" => /\bp\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/ }
    )
  end
end

module Integrations
  module Providers
    # A source's details carry its ingest token, which writes logs for anyone who has it.
    Betterstack = Provider.new(
      key: "betterstack", redacted_fields: %w[token], adapter: "Integrations::Capabilities::Betterstack", health_probe: "Integrations::HealthProbes::Betterstack"
    )
  end
end

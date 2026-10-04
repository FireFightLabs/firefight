module Integrations
  module Providers
    # Neon's compute states (init, active, idle) and branch states, from the Neon API's EndpointState and BranchState.
    Neon = Provider.new(
      key: "neon", adapter: "Integrations::Capabilities::Neon", map_reader: "Integrations::MapReaders::Neon",
      source_links: "Integrations::SourceLinks::Neon",
      status_words: { "idle" => "sleeping", "init" => "starting", "disabled" => "stopped", "archived" => "stopped" }
    )
  end
end

module Integrations
  module Providers
    # A connection string carries the role's password, and Neon's own server withholds it in read only mode, so it is never
    # read. A credential Neon makes or rotates is answered whole, so neither runs here. A reset role's password is
    # redacted from the answer, which still says the reset happened.
    # Neon's compute states (init, active, idle) and branch states, from the Neon API's EndpointState and BranchState. An
    # archived branch is sleeping, since Neon archives a branch nobody has used for a while and wakes it when it is used.
    Neon = Provider.new(
      key: "neon", adapter: "Integrations::Capabilities::Neon", map_reader: "Integrations::MapReaders::Neon",
      map_events: "Integrations::MapEventSources::Neon",
      source_links: "Integrations::SourceLinks::Neon",
      status_words: { "idle" => "sleeping", "init" => "starting", "disabled" => "stopped", "archived" => "sleeping" },
      error_reader: "Integrations::ErrorReaders::Neon",
      redacted_fields: %w[password],
      withheld_tools: {
        "get_connection_string" => "A connection string holds the role's password, so Firefight never reads it. Read the branch, " \
                                   "database and role by name instead, with describe_branch or list_branch_computes.",
        "create_credential" => "A new credential's answer is the secret itself, so Firefight never makes one here. Make it in Neon's console.",
        "rotate_credential" => "A rotated credential's answer is the secret itself, so Firefight never rotates one here. Rotate it in Neon's console."
      }
    )
  end
end

module Integrations
  module Providers
    # Railway's deployment statuses (schema, enum DeploymentStatus) in Firefight's words.
    Railway = Provider.new(
      key: "railway",
      pack: "Integrations::Packs::Railway",
      adapter: "Integrations::Capabilities::Railway",
      map_events: "Integrations::MapEventSources::Railway",
      read_guard: "Integrations::ReadGuards::Railway",
      status_words: {
        "initializing" => "pending", "waiting" => "pending", "needs_approval" => "pending",
        "skipped" => "stopped", "removing" => "stopped", "removed" => "stopped"
      }
    )
  end
end

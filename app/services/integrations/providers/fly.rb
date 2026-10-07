module Integrations
  module Providers
    # Fly's app statuses (superfly/fly-go, flaps_apps.go: deployed, suspended, pending) and Managed Postgres statuses
    # (Machines spec, PostgresCluster status) in Firefight's words.
    Fly = Provider.new(
      key: "fly",
      pack: "Integrations::Packs::Fly",
      adapter: "Integrations::Capabilities::Fly",
      map_events: "Integrations::MapEventSources::Fly",
      status_words: {
        "suspended" => "stopped",
        "creating" => "pending", "initializing" => "starting", "deleting" => "pending", "deleted" => "stopped"
      }
    )
  end
end

module Integrations
  module Providers
    # status_words: Cloud SQL, Compute Engine, GKE and Cloud Run states, as their APIs write them.
    GoogleCloud = Provider.new(
      key: "google_cloud",
      pack: "Integrations::Packs::GoogleCloud",
      adapter: "Integrations::Capabilities::GoogleCloud",
      map_events: "Integrations::MapEventSources::GoogleCloud",
      status_words: {
        "runnable" => "running", "provisioning" => "pending", "reconciling" => "pending", "repairing" => "pending",
        "pending_create" => "pending", "pending_delete" => "pending", "maintenance" => "pending", "online_maintenance" => "pending",
        "stopping" => "stopped", "stopped" => "stopped", "suspending" => "stopped", "suspended" => "stopped", "terminated" => "stopped",
        "pending_stop" => "stopped", "deprovisioning" => "stopped"
      }
    )
  end
end

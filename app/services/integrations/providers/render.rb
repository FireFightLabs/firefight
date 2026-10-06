module Integrations
  module Providers
    # Render's deploy statuses (spec, deployStatus) and datastore statuses (spec, databaseStatus) in Firefight's words. A
    # suspended service is set by the pack from its suspended field.
    Render = Provider.new(
      key: "render",
      pack: "Integrations::Packs::Render",
      adapter: "Integrations::Capabilities::Render",
      map_events: "Integrations::MapEventSources::Render",
      status_words: {
        "live" => "running", "created" => "deploying", "build_in_progress" => "deploying", "update_in_progress" => "deploying",
        "pre_deploy_in_progress" => "deploying", "build_failed" => "failed", "update_failed" => "failed", "pre_deploy_failed" => "failed",
        "canceled" => "stopped", "deactivated" => "stopped", "suspended" => "stopped",
        "available" => "ready", "creating" => "pending", "recovery_in_progress" => "pending", "config_restart" => "pending",
        "updating_instance" => "pending", "maintenance_in_progress" => "pending", "maintenance_scheduled" => "ready",
        "recovery_failed" => "failed"
      }
    )
  end
end

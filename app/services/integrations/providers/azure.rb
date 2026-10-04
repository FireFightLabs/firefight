module Integrations
  module Providers
    # status_words: App Service, Container Apps, Azure SQL and PostgreSQL flexible server states, as Resource Manager
    # writes them, lowercased.
    Azure = Provider.new(
      key: "azure",
      pack: "Integrations::Packs::Azure",
      adapter: "Integrations::Capabilities::Azure",
      status_words: {
        "online" => "running", "succeeded" => "ready", "progressing" => "deploying", "inprogress" => "in_progress",
        "suspended" => "stopped", "canceled" => "stopped", "deleting" => "stopped", "dropping" => "stopped", "disabled" => "stopped",
        "shutdown" => "stopped", "stopping" => "stopped", "restoring" => "pending", "recoverypending" => "pending",
        "recovering" => "pending", "copying" => "pending", "pausing" => "pending", "updating" => "pending", "creating" => "starting",
        "resuming" => "starting", "standby" => "ready", "autoclosed" => "paused", "scaling" => "resizing",
        "offlinechangingdwperformancetiers" => "resizing", "onlinechangingdwperformancetiers" => "resizing", "suspect" => "failed",
        "emergencymode" => "failed", "offline" => "down", "offlinesecondary" => "down", "inaccessible" => "unavailable"
      }
    )
  end
end

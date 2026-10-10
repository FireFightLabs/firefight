module Integrations
  module Providers
    Kubernetes = Provider.new(
      key: "kubernetes",
      pack: "Integrations::Packs::Kubernetes",
      adapter: "Integrations::Capabilities::Kubernetes",
      map_events: "Integrations::MapEventSources::Kubernetes",
      read_guard: "Integrations::ReadGuards::Kubernetes",
      cli: "Integrations::Clis::Kubernetes",
      # The words Packs::Kubernetes.state_of gives a workload, as Firefight reads them.
      status_words: { "scaled down" => "stopped", "progressing" => "deploying", "scheduled" => "ready", "succeeded" => "completed",
                      "suspended" => "paused" }
    )
  end
end

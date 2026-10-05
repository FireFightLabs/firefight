module Integrations
  module Providers
    Kubernetes = Provider.new(
      key: "kubernetes",
      pack: "Integrations::Packs::Kubernetes",
      adapter: "Integrations::Capabilities::Kubernetes",
      # The words Packs::Kubernetes.state_of gives a workload, as Firefight reads them.
      status_words: { "scaled down" => "stopped", "progressing" => "deploying", "scheduled" => "ready", "succeeded" => "completed",
                      "suspended" => "paused" }
    )
  end
end

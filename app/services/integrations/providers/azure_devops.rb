module Integrations
  module Providers
    # An Azure DevOps personal access token is 84 characters with AZDO at positions 76 to 80 (Use personal access tokens,
    # PAT format), a shape the generic patterns miss, so it is replaced wherever an answer carries one. A pipeline on the
    # map reads as its newest finished run went (BuildResult), or as switched off when its queue is (DefinitionQueueStatus).
    AzureDevops = Provider.new(
      key: "azure_devops",
      pack: "Integrations::Packs::AzureDevops",
      adapter: "Integrations::Capabilities::AzureDevops",
      map_events: "Integrations::MapEventSources::AzureDevops",
      read_guard: "Integrations::ReadGuards::AzureDevops",
      redacted_patterns: { "azure_devops_token" => /\b[A-Za-z0-9]{76}AZDO[A-Za-z0-9]{4}\b/ },
      status_words: { "succeeded" => "success", "partiallysucceeded" => "success", "canceled" => "stopped", "disabled" => "stopped" }
    )
  end
end

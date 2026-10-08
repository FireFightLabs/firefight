module Integrations
  module Providers
    # redacted_patterns: a workflow webhook trigger's address, which starts a run for anyone who has it, so Northflank
    # treats it as a credential (docs, Run a workflow using a webhook).
    # status_words: an addon's states, as the API's addon list writes them (@northflank/js-client, ListAddonsResult),
    # lowercased, for those that are not already Firefight's.
    Northflank = Provider.new(
      key: "northflank",
      pack: "Integrations::Packs::Northflank",
      adapter: "Integrations::Capabilities::Northflank",
      map_events: "Integrations::MapEventSources::Northflank",
      read_guard: "Integrations::ReadGuards::Northflank",
      redacted_patterns: { "northflank_webhook" => %r{webhooks\.northflank\.com/[^\s"'<>)\]]+}i },
      status_words: {
        "predeployment" => "pending", "triggerallocation" => "pending", "allocating" => "starting", "postdeployment" => "starting",
        "scaling" => "resizing", "upgrading" => "deploying", "resetting" => "pending", "backup" => "in_progress",
        "restore" => "pending", "errorallocating" => "failed", "deleting" => "stopped", "deleted" => "stopped"
      }
    )
  end
end

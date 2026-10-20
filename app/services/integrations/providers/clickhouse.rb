module Integrations
  module Providers
    # Service states from the Cloud API's Service schema, and ClickPipe states from its ClickPipe schema, that are not
    # already Firefight's own words. Its server only reads, so scaling a service is Firefight's own call to the Cloud API.
    Clickhouse = Provider.new(
      key: "clickhouse", adapter: "Integrations::Capabilities::Clickhouse", map_reader: "Integrations::MapReaders::Clickhouse",
      map_events: "Integrations::MapEventSources::Clickhouse", pack: "Integrations::Packs::Clickhouse",
      baseline_reader: "Integrations::BaselineReaders::Clickhouse", source_links: "Integrations::SourceLinks::Clickhouse",
      status_words: {
        "idle" => "sleeping", "awaking" => "starting", "provisioning" => "pending", "stopping" => "pending", "terminating" => "pending",
        "softdeleting" => "pending", "terminated" => "stopped", "softdeleted" => "stopped", "partially_running" => "degraded",
        "setup" => "pending", "snapshot" => "pending", "modifying" => "pending", "resync" => "pending", "pausing" => "pending",
        "internalerror" => "failed"
      }
    )
  end
end

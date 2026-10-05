module Integrations
  module Providers
    # Service states from the Cloud API's Service schema that are not already Firefight's own words.
    Clickhouse = Provider.new(
      key: "clickhouse", adapter: "Integrations::Capabilities::Clickhouse", map_reader: "Integrations::MapReaders::Clickhouse",
      baseline_reader: "Integrations::BaselineReaders::Clickhouse", source_links: "Integrations::SourceLinks::Clickhouse",
      status_words: {
        "idle" => "sleeping", "awaking" => "starting", "provisioning" => "pending", "stopping" => "pending", "terminating" => "pending",
        "softdeleting" => "pending", "terminated" => "stopped", "softdeleted" => "stopped", "partially_running" => "degraded"
      }
    )
  end
end

module Integrations
  module Providers
    # A Redis database's suspended state from the Developer API, and the reader's word for a QStash user that is not active.
    Upstash = Provider.new(
      key: "upstash", adapter: "Integrations::Capabilities::Upstash", map_reader: "Integrations::MapReaders::Upstash",
      baseline_reader: "Integrations::BaselineReaders::Upstash", source_links: "Integrations::SourceLinks::Upstash",
      status_words: { "suspended" => "stopped", "inactive" => "stopped" }
    )
  end
end

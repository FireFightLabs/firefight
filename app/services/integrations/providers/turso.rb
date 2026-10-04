module Integrations
  module Providers
    # The map reader says which of a database's reads and writes Turso blocks, and either leaves it unusable for that work.
    Turso = Provider.new(
      key: "turso", adapter: "Integrations::Capabilities::Turso", map_reader: "Integrations::MapReaders::Turso",
      status_words: { "reads blocked" => "unavailable", "writes blocked" => "unavailable", "reads and writes blocked" => "unavailable" }
    )
  end
end

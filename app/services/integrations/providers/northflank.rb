module Integrations
  module Providers
    Northflank = Provider.new(
      key: "northflank",
      pack: "Integrations::Packs::Northflank",
      adapter: "Integrations::Capabilities::Northflank",
      read_guard: "Integrations::ReadGuards::Northflank"
    )
  end
end

module Integrations
  module Providers
    Postgresql = Provider.new(key: "postgresql", pack: "Integrations::Packs::Postgres", adapter: "Integrations::Capabilities::Postgres")
  end
end

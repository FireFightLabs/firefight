module Integrations
  module Providers
    Convex = Provider.new(
      key: "convex",
      pack: "Integrations::Packs::Convex",
      adapter: "Integrations::Capabilities::Convex"
    )
  end
end

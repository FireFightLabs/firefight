module Integrations
  module Providers
    Fly = Provider.new(
      key: "fly",
      pack: "Integrations::Packs::Fly",
      adapter: "Integrations::Capabilities::Fly"
    )
  end
end

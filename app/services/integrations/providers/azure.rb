module Integrations
  module Providers
    Azure = Provider.new(
      key: "azure",
      pack: "Integrations::Packs::Azure",
      adapter: "Integrations::Capabilities::Azure"
    )
  end
end

module Integrations
  module Providers
    Railway = Provider.new(
      key: "railway",
      pack: "Integrations::Packs::Railway",
      adapter: "Integrations::Capabilities::Railway"
    )
  end
end

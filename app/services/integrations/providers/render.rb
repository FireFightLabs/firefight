module Integrations
  module Providers
    Render = Provider.new(
      key: "render",
      pack: "Integrations::Packs::Render",
      adapter: "Integrations::Capabilities::Render"
    )
  end
end

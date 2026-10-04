module Integrations
  module Providers
    Modal = Provider.new(
      key: "modal",
      pack: "Integrations::Packs::Modal",
      adapter: "Integrations::Capabilities::Modal"
    )
  end
end

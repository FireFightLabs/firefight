module Integrations
  module Providers
    TriggerDev = Provider.new(
      key: "trigger_dev",
      pack: "Integrations::Packs::TriggerDev",
      adapter: "Integrations::Capabilities::TriggerDev"
    )
  end
end

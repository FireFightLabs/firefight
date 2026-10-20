module Integrations
  module Providers
    TriggerDev = Provider.new(
      key: "trigger_dev",
      pack: "Integrations::Packs::TriggerDev",
      adapter: "Integrations::Capabilities::TriggerDev",
      map_events: "Integrations::MapEventSources::TriggerDev",
      read_guard: "Integrations::ReadGuards::TriggerDev"
    )
  end
end

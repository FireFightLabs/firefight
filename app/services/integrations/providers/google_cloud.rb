module Integrations
  module Providers
    GoogleCloud = Provider.new(
      key: "google_cloud",
      pack: "Integrations::Packs::GoogleCloud",
      adapter: "Integrations::Capabilities::GoogleCloud"
    )
  end
end

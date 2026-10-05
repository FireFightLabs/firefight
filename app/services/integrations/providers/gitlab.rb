module Integrations
  module Providers
    Gitlab = Provider.new(key: "gitlab", pack: "Integrations::Packs::Gitlab", adapter: "Integrations::Capabilities::Gitlab")
  end
end

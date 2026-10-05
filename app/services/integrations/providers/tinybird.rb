module Integrations
  module Providers
    Tinybird = Provider.new(key: "tinybird", pack: "Integrations::Packs::Tinybird", adapter: "Integrations::Capabilities::Tinybird")
  end
end

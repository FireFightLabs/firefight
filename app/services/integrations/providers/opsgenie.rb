module Integrations
  module Providers
    Opsgenie = Provider.new(key: "opsgenie", pack: "Integrations::Packs::Opsgenie", pager: "Integrations::Pagers::Opsgenie")
  end
end

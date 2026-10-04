module Integrations
  module Providers
    Vercel = Provider.new(
      key: "vercel",
      pack: "Integrations::Packs::Vercel",
      adapter: "Integrations::Capabilities::Vercel"
    )
  end
end

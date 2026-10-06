module Integrations
  module Providers
    Netlify = Provider.new(
      key: "netlify",
      pack: "Integrations::Packs::Netlify",
      adapter: "Integrations::Capabilities::Netlify",
      map_events: "Integrations::MapEventSources::Netlify",
      # A site's state, which is current for one that serves (openapi swagger.yml, site.state).
      status_words: { "current" => "ready" }
    )
  end
end

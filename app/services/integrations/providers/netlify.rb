module Integrations
  module Providers
    Netlify = Provider.new(
      key: "netlify",
      pack: "Integrations::Packs::Netlify",
      adapter: "Integrations::Capabilities::Netlify",
      map_events: "Integrations::MapEventSources::Netlify",
      read_guard: "Integrations::ReadGuards::Netlify",
      # A build hook's address starts a build for anyone who has it (docs, Build hooks), so it is a credential wherever it
      # appears in an answer.
      redacted_patterns: { "netlify_build_hook" => %r{api\.netlify\.com/build_hooks/[^\s"'<>)\]]+}i },
      # A site's state, which is current for one that serves (openapi swagger.yml, site.state).
      status_words: { "current" => "ready" }
    )
  end
end

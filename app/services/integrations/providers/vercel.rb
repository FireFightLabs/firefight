module Integrations
  module Providers
    # Vercel's deployment states (spec, readyState) in Firefight's words.
    Vercel = Provider.new(
      key: "vercel",
      pack: "Integrations::Packs::Vercel",
      adapter: "Integrations::Capabilities::Vercel",
      map_events: "Integrations::MapEventSources::Vercel",
      read_guard: "Integrations::ReadGuards::Vercel",
      # A deploy hook's address starts a deployment for anyone who has it (docs, deploy-hooks), and a project answers its
      # hooks with their addresses (spec, getProject link.deployHooks), so it is a credential wherever it appears.
      redacted_patterns: { "vercel_deploy_hook" => %r{api\.vercel\.com/v1/integrations/deploy/[^\s"'<>)\]]+}i },
      status_words: { "initializing" => "pending", "canceled" => "stopped" }
    )
  end
end

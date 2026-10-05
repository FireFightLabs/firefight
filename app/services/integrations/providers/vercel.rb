module Integrations
  module Providers
    # Vercel's deployment states (spec, readyState) in Firefight's words.
    Vercel = Provider.new(
      key: "vercel",
      pack: "Integrations::Packs::Vercel",
      adapter: "Integrations::Capabilities::Vercel",
      status_words: { "initializing" => "pending", "canceled" => "stopped" }
    )
  end
end

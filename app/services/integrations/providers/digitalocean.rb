module Integrations
  module Providers
    Digitalocean = Provider.new(
      key: "digitalocean",
      pack: "Integrations::Packs::Digitalocean",
      adapter: "Integrations::Capabilities::Digitalocean",
      # DigitalOcean's own words (digitalocean/openapi): a Droplet's status, a database cluster's status, and an App
      # Platform deployment's phase.
      status_words: {
        "new" => "starting", "off" => "stopped", "archive" => "stopped",
        "online" => "running", "creating" => "pending", "migrating" => "pending", "forking" => "pending",
        "pending_build" => "pending", "pending_deploy" => "pending", "superseded" => "stopped", "canceled" => "stopped"
      }
    )
  end
end

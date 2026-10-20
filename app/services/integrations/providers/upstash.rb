module Integrations
  module Providers
    # A Redis database's suspended state from the Developer API, the reader's word for a QStash user that is not active,
    # and a Box's states from the Box SDK's BoxStatus, where idle is up and waiting for work.
    # Upstash's server answers a database or a QStash user with its credentials when asked, the database's password and
    # REST tokens and QStash's tokens and signing keys, and none of them has a shape Firefight would know as a secret.
    Upstash = Provider.new(
      key: "upstash", adapter: "Integrations::Capabilities::Upstash", map_reader: "Integrations::MapReaders::Upstash",
      baseline_reader: "Integrations::BaselineReaders::Upstash", source_links: "Integrations::SourceLinks::Upstash",
      mitigation_reader: "Integrations::MitigationReaders::Upstash", pack: "Integrations::Packs::Upstash",
      status_words: { "suspended" => "stopped", "inactive" => "stopped", "idle" => "ready", "creating" => "starting", "deleted" => "stopped" },
      error_reader: "Integrations::ErrorReaders::Upstash",
      redacted_fields: %w[password rest_token read_only_rest_token token read_only_token current_signing_key next_signing_key]
    )
  end
end

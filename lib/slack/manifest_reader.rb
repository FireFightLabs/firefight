module Slack
  class ManifestReader
    def self.scopes_for_environment(env = Rails.env)
      manifest_path = Rails.root.join("config", "slack_manifests", "#{env}.yml")

      unless File.exist?(manifest_path)
        Rails.logger.warn "Slack manifest not found: #{manifest_path}"
        return { user_scope: "", bot_scope: "" }
      end

      manifest = YAML.load_file(manifest_path)
      oauth_config = manifest.dig("oauth_config", "scopes") || {}

      user_scopes = Array(oauth_config["user"]).join(",")
      bot_scopes = Array(oauth_config["bot"]).join(",")

      # Combine for OmniAuth (user scopes + bot scopes)
      combined_scopes = [ user_scopes, bot_scopes ].reject(&:empty?).join(",")

      {
        scope: combined_scopes,          # All scopes combined
        user_scope: user_scopes,         # Just user scopes
        bot_scope: bot_scopes            # Just bot scopes
      }
    end
  end
end

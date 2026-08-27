module Slack
  class ManifestReader
    def self.scopes_for_environment(env = Rails.env)
      manifest_path = manifest_for(env)

      unless manifest_path
        Rails.logger.warn "Slack manifest not found for #{env}"
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

    # Deployments keep a manifest per environment, since each one is a separate
    # Slack app with its own URLs. Anyone else has the template, which carries
    # the same scopes.
    def self.manifest_for(env)
      [ "#{env}.yml", "template.yml" ]
        .map { |name| Rails.root.join("config", "slack_manifests", name) }
        .find { |path| File.exist?(path) }
    end
  end
end

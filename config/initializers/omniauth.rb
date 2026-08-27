# Load custom strategies and helpers
require Rails.root.join("lib", "omniauth", "strategies", "slack")
require Rails.root.join("lib", "omniauth", "strategies", "slack_openid")
require Rails.root.join("lib", "slack", "manifest_reader")

# Read bot scopes from Slack manifest (used for the install step only)
slack_scopes = Slack::ManifestReader.scopes_for_environment(Rails.env)

slack_client_id     = ENV["SLACK_CLIENT_ID"]     || Rails.application.credentials.dig(:slack, :client_id)
slack_client_secret = ENV["SLACK_CLIENT_SECRET"] || Rails.application.credentials.dig(:slack, :client_secret)

Rails.application.config.middleware.use OmniAuth::Builder do
  # Step 1, identity only (Slack shows its native workspace picker).
  # Used for every dashboard sign-in. No bot scopes, no install.
  provider :slack_openid, slack_client_id, slack_client_secret

  # Step 2, bot install. Only triggered when a user without an existing
  # workspace explicitly chooses to install Firefight. The team_id is read
  # from session (set by the OIDC handler) so the picker is skipped.
  # Only bot scopes are requested here, user identity was already established
  # by the :slack_openid provider in step 1.
  provider :slack, slack_client_id, slack_client_secret,
    scope: slack_scopes[:bot_scope],
    setup: ->(env) {
      pending_team_id = env["rack.session"]&.dig("pending_team_id") || env["rack.session"]&.dig(:pending_team_id)
      env["omniauth.strategy"].options[:authorize_params] = { team: pending_team_id } if pending_team_id.present?
    }
end

# Configure OmniAuth
OmniAuth.config.allowed_request_methods = [ :get, :post ]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}

# Silence OmniAuth's strategy-level debug chatter ("Setup endpoint detected…")
# during tests. Gets its own logger so we don't lower Rails.logger globally.
OmniAuth.config.logger = Logger.new(IO::NULL) if Rails.env.test?

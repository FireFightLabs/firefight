# Load custom strategies and helpers
require Rails.root.join("lib", "omniauth", "strategies", "slack")
require Rails.root.join("lib", "slack", "manifest_reader")

# Read scopes from Slack manifest based on current environment
slack_scopes = Slack::ManifestReader.scopes_for_environment(Rails.env)

Rails.application.config.middleware.use OmniAuth::Builder do
  # Build provider options
  provider_options = {
    scope: slack_scopes[:scope],
    user_scope: slack_scopes[:user_scope]
  }

  # If SLACK_TEAM_ID env var is set, force that specific workspace
  if ENV["SLACK_TEAM_ID"].present?
    provider_options[:authorize_params] = { team: ENV["SLACK_TEAM_ID"] }
  end

  provider :slack,
    Rails.application.credentials.dig(:slack, :client_id),
    Rails.application.credentials.dig(:slack, :client_secret),
    **provider_options
end

# Configure OmniAuth
OmniAuth.config.allowed_request_methods = [ :get, :post ]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}

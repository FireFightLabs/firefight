require Rails.root.join("lib", "omniauth", "strategies", "slack")
require Rails.root.join("lib", "omniauth", "strategies", "slack_openid")
require Rails.root.join("lib", "slack", "manifest_reader")

slack_scopes = Slack::ManifestReader.scopes_for_environment(Rails.env)

slack_client_id     = ENV["SLACK_CLIENT_ID"]     || Rails.application.credentials.dig(:slack, :client_id)
slack_client_secret = ENV["SLACK_CLIENT_SECRET"] || Rails.application.credentials.dig(:slack, :client_secret)

google_client_id     = ENV["GOOGLE_CLIENT_ID"].presence
google_client_secret = ENV["GOOGLE_CLIENT_SECRET"].presence
Rails.application.config.x.google_sign_in = google_client_id.present? && google_client_secret.present?

Rails.application.config.middleware.use OmniAuth::Builder do
  # Identity only, used for every dashboard sign-in. Slack shows its own workspace picker.
  provider :slack_openid, slack_client_id, slack_client_secret

  # Bot install, only when a user with no workspace chooses to install. The team_id from the
  # OIDC step skips the picker, and identity was already established there.
  provider :slack, slack_client_id, slack_client_secret,
    scope: slack_scopes[:bot_scope],
    setup: ->(env) {
      pending_team_id = env["rack.session"]&.dig("pending_team_id") || env["rack.session"]&.dig(:pending_team_id)
      env["omniauth.strategy"].options[:authorize_params] = { team: pending_team_id } if pending_team_id.present?
    }

  # Identity only. select_account shows the account picker even when one Google account is signed in.
  if Rails.application.config.x.google_sign_in
    provider :google_oauth2, google_client_id, google_client_secret,
      scope: "openid,email,profile", prompt: "select_account", access_type: "online"
  end
end

OmniAuth.config.allowed_request_methods = [ :get, :post ]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}

# Own logger so tests silence OmniAuth without lowering Rails.logger.
OmniAuth.config.logger = Logger.new(IO::NULL) if Rails.env.test?

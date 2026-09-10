module SlackConstants
  API_BASE_URL = "https://slack.com/api"

  # Slack expires a trigger_id 3 seconds after the command, views.open must happen inside that.
  TRIGGER_ID_EXPIRATION = 3.seconds

  # Requests with an older timestamp are treated as replays.
  REPLAY_ATTACK_WINDOW = 5.minutes

  SIGNATURE_VERSION = "v0"

  # Fails at boot rather than on the first webhook.
  SIGNING_SECRET = (ENV["SLACK_SIGNING_SECRET"] || Rails.application.credentials.dig(:slack, :signing_secret)).tap do |secret|
    raise "Missing SLACK_SIGNING_SECRET env var or slack.signing_secret in credentials." if secret.blank?
  end.freeze
end

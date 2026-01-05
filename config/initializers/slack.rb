# Slack-specific constants and configuration
# Loaded at application boot time

module SlackConstants
  # Slack API base URL
  API_BASE_URL = "https://slack.com/api"

  # Slack trigger_id expires 3 seconds after slash command is issued
  # Jobs must call views.open within this window
  TRIGGER_ID_EXPIRATION = 3.seconds

  # Slack signature replay attack prevention window
  # Reject requests with timestamps older than this
  REPLAY_ATTACK_WINDOW = 5.minutes

  # Slack signature version prefix
  SIGNATURE_VERSION = "v0"

  # Load signing secret from credentials at boot time
  # Fail fast if missing - better than runtime errors
  SIGNING_SECRET = Rails.application.credentials.dig(:slack, :signing_secret).tap do |secret|
    if secret.blank?
      raise "Missing slack.signing_secret in credentials. " \
            "Run: EDITOR=\"code --wait\" bin/rails credentials:edit --environment #{Rails.env}"
    end
  end.freeze
end

# Flipper preloads every flag at the start of each request by default. Load them only when a request checks one,
# so Slack webhooks and API calls that never ask pay no extra query.
Rails.application.config.flipper.preload = false

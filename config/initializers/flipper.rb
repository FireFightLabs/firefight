# Load flags only when a request checks one, not on every request.
Rails.application.config.flipper.preload = false

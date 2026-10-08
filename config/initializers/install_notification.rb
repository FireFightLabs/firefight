# Webhook URL for the team's notes on new workspaces and AI credit. Unset sends nothing.
Rails.application.config.x.install_notification_webhook_url = ENV["INSTALL_NOTIFICATION_WEBHOOK_URL"].presence

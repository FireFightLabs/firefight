# Webhook URL for new install notes. Unset sends nothing.
Rails.application.config.x.install_notification_webhook_url = ENV["INSTALL_NOTIFICATION_WEBHOOK_URL"].presence

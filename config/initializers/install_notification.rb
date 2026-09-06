# Where to send a note when a new workspace installs. Unset means no note is
# sent, which is the self-hosted default. Hosted production points this at a
# chat webhook so the team hears about every install as it happens.
Rails.application.config.x.install_notification_webhook_url = ENV["INSTALL_NOTIFICATION_WEBHOOK_URL"].presence

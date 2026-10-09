# Webhook URL for the team's notes on new workspaces and AI credit. Unset sends nothing.
Rails.application.config.x.install_notification_webhook_url = ENV["INSTALL_NOTIFICATION_WEBHOOK_URL"].presence

# Below this many dollars left on a key of the deployment's own, the team is alerted.
Rails.application.config.x.ai_low_balance_usd = Float(ENV["FIREFIGHT_AI_LOW_BALANCE_USD"].presence || 10, exception: false) || 10.0

# A Slack user id such as U012AB3CD, tagged in each AI account alert. Unset tags nobody.
Rails.application.config.x.ai_alert_slack_user_id = ENV["FIREFIGHT_AI_ALERT_SLACK_USER_ID"].presence

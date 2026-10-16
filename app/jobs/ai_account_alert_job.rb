# Posts one AiAccountAlert to the team webhook, naming the person FIREFIGHT_AI_ALERT_SLACK_USER_ID gives.
class AiAccountAlertJob < ApplicationJob
  queue_as :default

  retry_on TeamWebhook::DeliveryFailed, wait: 30.seconds, attempts: 3 do |job, error|
    Rails.logger.error({ event: "ai.account_alert_failed", provider: job.arguments.first, kind: job.arguments.second, error: error.message }.to_json)
  end

  def perform(provider, kind = AiAccountAlert::OUT_OF_CREDIT, remaining = nil, usage = nil)
    return unless TeamWebhook.configured?

    words = AiAccountAlert.words(provider, kind, remaining, usage)
    return unless words

    TeamWebhook.post!({ text: words }, mention: Rails.configuration.x.ai_alert_slack_user_id)
    Rails.logger.info({ event: "ai.account_alerted", provider: provider, kind: kind }.to_json)
  end
end

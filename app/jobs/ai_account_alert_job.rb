# Tells the people running Firefight that an AI account ran out of credit, once, when it does.
class AiAccountAlertJob < ApplicationJob
  queue_as :default

  retry_on TeamWebhook::DeliveryFailed, wait: 30.seconds, attempts: 3 do |job, error|
    Rails.logger.error({ event: "ai.out_of_credit_alert_failed", provider: job.arguments.first, error: error.message }.to_json)
  end

  def perform(provider)
    account = AiAccount.out_of_credit.find_by(provider: provider)
    return unless account && TeamWebhook.configured?

    TeamWebhook.post!(text: "The #{provider} AI account ran out of credit at #{account.out_of_credit_since.utc.strftime('%H:%M UTC on %-d %B')}. " \
                            "Halon cannot answer in any workspace that uses it until credit is added. It is listed under Needs attention in the operator console.")
    Rails.logger.info({ event: "ai.out_of_credit_alerted", provider: provider }.to_json)
  end
end

# Posts one AiAccountAlert to the team webhook, naming the person FIREFIGHT_AI_ALERT_SLACK_USER_ID gives.
class AiAccountAlertJob < ApplicationJob
  queue_as :default

  retry_on TeamWebhook::DeliveryFailed, wait: 30.seconds, attempts: 3 do |job, error|
    Rails.logger.error({ event: "ai.account_alert_failed", provider: job.arguments.first, kind: job.arguments.second, error: error.message }.to_json)
  end

  def perform(provider, kind = AiAccountAlert::OUT_OF_CREDIT, remaining = nil, usage = nil)
    return unless TeamWebhook.configured?

    words = kind == AiAccountAlert::LOW_BALANCE ? low_balance(provider, remaining, usage) : out_of_credit(provider)
    return unless words

    TeamWebhook.post!({ text: words }, mention: Rails.configuration.x.ai_alert_slack_user_id)
    Rails.logger.info({ event: "ai.account_alerted", provider: provider, kind: kind }.to_json)
  end

  private

  # Nil once a call has answered again since, so a refilled account is not reported out.
  def out_of_credit(provider)
    account = AiAccount.out_of_credit.find_by(provider: provider)
    return unless account

    "The #{provider} AI account ran out of credit at #{account.out_of_credit_since.utc.strftime('%H:%M UTC on %-d %B')}. " \
      "Halon cannot answer in any workspace that uses it until credit is added. It is listed under Needs attention in the operator console."
  end

  def low_balance(provider, remaining, usage)
    "The #{provider} AI account is running low. It has #{dollars(remaining)} of credit left, and has spent #{dollars(usage)} in all. " \
      "Alerts start below #{dollars(Rails.configuration.x.ai_low_balance_usd)}. Add credit before Halon stops answering."
  end

  def dollars(amount) = format("$%.2f", amount.to_f)
end

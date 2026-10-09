# Tells the people running Firefight that one of the deployment's own AI keys was refused for credit or is running low,
# on the team webhook. One alert per key per AiAccount::ALERT_INTERVAL, whatever the reason, so a key refused on every
# call or low on every hourly check does not post each time. With no webhook set nothing is sent, and that is logged.
module AiAccountAlert
  OUT_OF_CREDIT = "out_of_credit".freeze
  LOW_BALANCE = "low_balance".freeze

  module_function

  def out_of_credit!(provider) = alert!(provider, OUT_OF_CREDIT)

  def low_balance!(provider, balance) = alert!(provider, LOW_BALANCE, balance.remaining, balance.usage)

  def alert!(provider, kind, *details)
    return false if provider.blank?

    unless TeamWebhook.configured?
      Rails.logger.info({ event: "ai.account_alert_unsent", provider: provider.to_s, kind: kind, reason: "no_webhook" }.to_json)
      return false
    end
    return false unless AiAccount.alert_due!(provider)

    AiAccountAlertJob.perform_later(provider.to_s, kind, *details)
    true
  end
end

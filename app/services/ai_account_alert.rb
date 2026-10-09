# Tells the people running Firefight that one of the deployment's own AI accounts was refused for credit or is running
# low, on the team webhook. Running out is told the moment it happens and then once per AiAccount::ALERT_INTERVAL while
# it stays out, so a key refused on every call does not post each time. Running low is told once per interval and is
# kept quiet by any alert inside it. With no webhook set nothing is sent, and that is logged.
module AiAccountAlert
  OUT_OF_CREDIT = "out_of_credit".freeze
  LOW_BALANCE = "low_balance".freeze

  module_function

  # fresh is the refusal that moved the account from credit to none.
  def out_of_credit!(provider, fresh: false)
    alert!(provider, OUT_OF_CREDIT) { AiAccount.out_of_credit_alert_due!(provider, fresh: fresh) }
  end

  def low_balance!(provider, account)
    alert!(provider, LOW_BALANCE, account.remaining, account.usage) { AiAccount.low_balance_alert_due!(provider) }
  end

  def alert!(provider, kind, *details)
    return false if provider.blank?

    unless TeamWebhook.configured?
      Rails.logger.info({ event: "ai.account_alert_unsent", provider: provider.to_s, kind: kind, reason: "no_webhook" }.to_json)
      return false
    end
    return false unless yield

    AiAccountAlertJob.perform_later(provider.to_s, kind, *details)
    true
  end
end

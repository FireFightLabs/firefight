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

  # What is posted, or nil once a call has answered again since, so a refilled account is not reported out.
  def words(provider, kind, remaining = nil, usage = nil)
    return low_balance_words(provider, remaining, usage) if kind == LOW_BALANCE

    account = AiAccount.out_of_credit.find_by(provider: provider)
    return unless account

    "The #{provider} AI account ran out of credit at #{account.out_of_credit_since.utc.strftime('%H:%M UTC on %-d %B')}. " \
      "Halon cannot answer in any workspace that uses it until credit is added. It is listed under Needs attention in the operator console."
  end

  def low_balance_words(provider, remaining, usage)
    "The #{provider} AI account is running low. It has #{dollars(remaining)} of credit left, and has spent #{dollars(usage)} in all. " \
      "Alerts start below #{dollars(Rails.configuration.x.ai_low_balance_usd)}. Add credit before Halon stops answering."
  end

  def dollars(amount) = format("$%.2f", amount.to_f)
end

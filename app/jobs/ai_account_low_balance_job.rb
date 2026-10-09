# Hourly, reads what each of the deployment's own keys may still spend, for the providers that say, and alerts the
# people running Firefight when one is below FIREFIGHT_AI_LOW_BALANCE_USD. A key with no spending limit of its own
# spends the whole account, which only a management key can read, so it is logged and not alerted on.
class AiAccountLowBalanceJob < ApplicationJob
  queue_as :background

  def perform
    FirefightAi::Balance.providers.each do |provider|
      balance = FirefightAi::Balance.key(provider)
      next unless balance

      if balance.unlimited?
        Rails.logger.info({ event: "ai.balance_unlimited", provider: provider }.to_json)
      elsif balance.remaining < Rails.configuration.x.ai_low_balance_usd
        AiAccountAlert.low_balance!(provider, balance)
      end
    end
  end
end

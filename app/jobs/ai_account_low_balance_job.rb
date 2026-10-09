# Hourly, reads what each of the deployment's own accounts holds, for the providers that say, and alerts the people
# running Firefight when one is below FIREFIGHT_AI_LOW_BALANCE_USD. Reading a balance takes its own key (OpenRouter's
# management key in OPENROUTER_MANAGEMENT_KEY), so without it nothing is read and that is logged.
class AiAccountLowBalanceJob < ApplicationJob
  queue_as :background

  def perform
    FirefightAi::Balance.unchecked.each do |provider, key_name|
      Rails.logger.info({ event: "ai.balance_unchecked", provider: provider, missing: key_name }.to_json)
    end
    FirefightAi::Balance.providers.each do |provider|
      account = FirefightAi::Balance.account(provider)
      next unless account

      AiAccountAlert.low_balance!(provider, account) if account.remaining < Rails.configuration.x.ai_low_balance_usd
    end
  end
end

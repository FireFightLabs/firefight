# Hourly, reads the balance of each account out of credit whose provider says it, so one that was refilled stops
# reading as out before anyone calls the model again.
class AiAccountBalanceJob < ApplicationJob
  queue_as :background

  # Below this the account runs out again within a few chats, so it is not counted as refilled.
  REFILLED_DOLLARS = 1.0

  def perform
    AiAccount.out_of_credit.find_each do |account|
      left = FirefightAi::Balance.remaining(account.provider)
      account.update_columns(balance_checked_at: Time.current)
      AiAccount.refilled!(account.provider) if left && left >= REFILLED_DOLLARS
    end
  end
end

# Every ten minutes, refreshes the tokens of accounts signed in through OAuth that expire soon, so a call never runs on
# an expired token. A refresh the provider refuses keeps the account out of use until someone signs in again.
class WorkspaceAiAccountTokenRefreshJob < ApplicationJob
  queue_as :background

  REFRESH_WITHIN = 15.minutes

  def perform
    WorkspaceAiAccount.enabled.where(kind: AiProviders::KIND_OAUTH).where(credentials_expire_at: ..REFRESH_WITHIN.from_now).includes(:workspace).find_each do |account|
      AiAccountSignIn.new(account.workspace).refresh!(account)
    end
  end
end

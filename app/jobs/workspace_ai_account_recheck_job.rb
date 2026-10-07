# Hourly, checks each workspace account kept out of use for running out of credit or having its key refused, with one
# tiny call each, so one that was refilled or fixed at the provider is used again without anyone pressing anything.
# A refusal costs nothing, and the admins were already told once.
class WorkspaceAiAccountRecheckJob < ApplicationJob
  queue_as :background

  def perform
    WorkspaceAiAccount.stuck.includes(:workspace).find_each do |account|
      WorkspaceAiAccountService.new(account.workspace).check!(account)
    end
  end
end

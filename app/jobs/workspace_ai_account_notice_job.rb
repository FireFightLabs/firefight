# Tells a workspace's admins, once, that one of its own AI accounts ran out of credit or had its key refused, and that
# Halon moved on to the next account.
class WorkspaceAiAccountNoticeJob < ApplicationJob
  queue_as :default

  def perform(account_id, notice)
    account = WorkspaceAiAccount.find_by(id: account_id)
    return unless account

    WorkspaceAiAccountService.new(account.workspace).notify_admins!(account, notice)
  end
end

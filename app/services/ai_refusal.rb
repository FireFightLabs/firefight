# A model call its payer refused for good. The payer is set aside from this call on, and whoever can fix it is told
# once, however many calls were refused together: a workspace's admins for its own account, the people running
# Firefight for the deployment's. The AI engine reports each such refusal here, and the code fix relay and the sign in
# refresh call the same steps.
module AiRefusal
  module_function

  def record!(payer, provider, error)
    return house_ran_out!(provider) if !payer&.own_account? && FirefightAi::Credit.from(error).out_of_credit?
    return unless payer&.own_account?
    return account_ran_out!(payer.account, error) if AiPayer.out_of_credit?(error)

    key_refused!(payer.account, error) if AiPayer.key_refused?(error)
  end

  def account_ran_out!(account, error)
    moved = account.ran_out!(error)
    WorkspaceAiAccountNoticeJob.perform_later(account.id, WorkspaceAiAccount::NOTICE_OUT_OF_CREDIT) if moved
    moved
  end

  def key_refused!(account, error)
    moved = account.key_refused!(error)
    WorkspaceAiAccountNoticeJob.perform_later(account.id, WorkspaceAiAccount::NOTICE_KEY_REFUSED) if moved
    moved
  end

  # The deployment's own account, whose alert goes to the people running Firefight.
  def house_ran_out!(provider)
    moved = AiAccount.ran_out!(provider)
    AiAccountAlertJob.perform_later(provider.to_s) if moved
    moved
  end
end

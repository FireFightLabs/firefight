# Who pays for one model call: one of the workspace's own AI accounts, its Firefight credits, the operator's keys on an
# install someone runs themselves, Firefight for its own workspaces, or nobody, when nothing can pay and no call is made.
AiPayer = Data.define(:paid_by, :account) do
  def self.account(account) = new(paid_by: Inference::PAID_BY_ACCOUNT, account: account)

  def self.house(paid_by) = new(paid_by: paid_by, account: nil)

  # The deployment's own account, for a call no workspace chose a payer for, such as an operator's rehearsal, the
  # regression judge or an embedding.
  def self.deployment(workspace)
    house(Entitlements.ai_account(workspace) == Entitlements::AI_ACCOUNT_OPERATOR ? Inference::PAID_BY_OPERATOR : Inference::PAID_BY_FIREFIGHT)
  end

  # A call for the deployment itself rather than for one workspace, such as embedding the providers' documentation. Only
  # the open-source backend runs on an operator's own keys, so every other build pays as Firefight.
  def self.deployment_only
    house(Entitlements.backend.is_a?(Entitlements::OpenSourceBackend) ? Inference::PAID_BY_OPERATOR : Inference::PAID_BY_FIREFIGHT)
  end

  # The provider refused for credit.
  def self.out_of_credit?(error)
    return true if error.is_a?(FirefightAi::OutOfCredit)

    error.is_a?(RubyLLM::Error) && FirefightAi::Credit.from(error).out_of_credit?
  end

  # The provider refused the account itself rather than the call, so the next account should take over.
  def self.key_refused?(error)
    error.is_a?(RubyLLM::UnauthorizedError) || error.is_a?(RubyLLM::ForbiddenError) ||
      (error.is_a?(FirefightAi::Error) && AiAccountError::KEY_REASONS.include?(error.reason))
  end

  def self.gives_way?(error) = out_of_credit?(error) || key_refused?(error)

  def own_account? = account.present?

  def nobody? = paid_by.nil?

  def ledger = { paid_by: paid_by, workspace_ai_account: account }

  def answered!(provider)
    own_account? ? account.answered! : AiAccount.answered!(provider)
  end
end

AiPayer.const_set(:NOBODY, AiPayer.new(paid_by: nil, account: nil))

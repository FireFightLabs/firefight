# What a person is told when a model call could not be paid for. It never names the provider. Who pays decides what
# was wrong and who can fix it: the workspace's own AI accounts and its Firefight credits are an admin's to fix under
# Settings, Workspace, the operator's keys are whoever runs Firefight's, and Firefight's own account is Firefight's,
# whose team is said to have been told only when an alert actually reaches it.
module AiCredit
  # FirefightAi::OutOfCredit's reason, as a job or a run records it.
  REASON = FirefightAi::OutOfCredit.name.demodulize
  ANSWER = "answer".freeze
  WHERE_TO_FIX = "An admin can fix this under Settings, Workspace, AI accounts".freeze

  def self.out?(error) = error.is_a?(FirefightAi::OutOfCredit)

  def self.recorded?(reason) = reason.to_s == REASON

  # "Halon cannot answer right now because ...", with what it could not do in place of answer.
  def self.cannot(workspace, doing = ANSWER)
    "Halon cannot #{doing} right now because #{why(workspace)}. #{who(workspace)}."
  end

  def self.why(workspace)
    case situation(workspace)
    when :no_account then "this workspace has no AI account set up"
    when :credits_used then "this workspace's Firefight credits are used up"
    when :key_refused then "this workspace's AI account refused its key"
    when :own_out then "this workspace's AI account is out of credit"
    when :firefight then "the AI account behind this workspace is out of credit"
    else "the AI account behind this Firefight is out of credit"
    end
  end

  def self.who(workspace)
    case situation(workspace)
    when :operator then "Whoever runs Firefight needs to add credit"
    when :firefight then AiAccount.alerting? ? "Firefight's team has been told" : "Firefight's team can see this"
    else WHERE_TO_FIX
    end
  end

  # The last payer in the workspace's order is the one that could not pay, so it decides what is said. The house comes
  # last, and when there is none the workspace's own accounts did.
  def self.situation(workspace)
    house = AiFunding.house_payer(workspace)
    return :operator if house&.paid_by == Inference::PAID_BY_OPERATOR
    # Credits that can still pay ran on Firefight's own account, so that account is what ran out.
    return :firefight if [ Inference::PAID_BY_FIREFIGHT, Inference::PAID_BY_CREDITS ].include?(house&.paid_by)
    return :credits_used if Entitlements.ai_credit(workspace)&.used?

    stuck = workspace.workspace_ai_accounts.stuck.last
    return :no_account unless stuck

    stuck.failing_since ? :key_refused : :own_out
  end
end

# What a person is told when a model call was refused because the AI account paying for it has no credit left. It
# never names the provider. Whose account it is decides who can add credit, so it is asked of Entitlements, and only
# a team an alert actually reaches is said to have been told.
module AiCredit
  # FirefightAi::OutOfCredit's reason, as a job or a run records it.
  REASON = FirefightAi::OutOfCredit.name.demodulize
  ANSWER = "answer".freeze

  def self.out?(error) = error.is_a?(FirefightAi::OutOfCredit)

  def self.recorded?(reason) = reason.to_s == REASON

  # "Halon cannot answer right now because ...", with what it could not do in place of answer.
  def self.cannot(workspace, doing = ANSWER)
    "Halon cannot #{doing} right now because #{why(workspace)}. #{who(workspace)}."
  end

  def self.why(workspace)
    holder = firefights?(workspace) ? "this workspace" : "this Firefight"
    "the AI account behind #{holder} is out of credit"
  end

  def self.who(workspace)
    return "Whoever runs Firefight needs to add credit" unless firefights?(workspace)

    AiAccount.alerting? ? "Firefight's team has been told" : "Firefight's team can see this"
  end

  def self.firefights?(workspace) = Entitlements.ai_account(workspace) == Entitlements::AI_ACCOUNT_FIREFIGHT
end

# What a person is told when a model call was refused because the AI account paying for it has no credit left. It
# never names the provider. Every workspace runs on the deployment's own account, so the people running it are the
# ones to tell, and whose account ran out is decided here alone.
module AiCredit
  # FirefightAi::OutOfCredit's reason, as a job or a run records it.
  REASON = FirefightAi::OutOfCredit.name.demodulize
  ANSWER = "answer".freeze

  def self.out?(error) = error.is_a?(FirefightAi::OutOfCredit)

  def self.recorded?(reason) = reason.to_s == REASON

  # "Halon cannot answer right now because ...", with what it could not do in place of answer.
  def self.cannot(workspace, doing = ANSWER)
    "Halon cannot #{doing} right now because #{why(workspace)}. #{told(workspace)}."
  end

  def self.why(_workspace) = "the AI account behind this workspace is out of credit"

  def self.told(_workspace) = "Firefight's team has been told"
end

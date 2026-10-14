# Decides a step a coding agent asked permission for. Halon judges it from what the agent did lately and what the
# change is for, and lets it go on or refuses it, with why. Where the change was asked for in a chat or a fix, Halon
# can leave it to the person instead, as a question in the same place as the agent's own, with the way it leans,
# which stands if nobody answers in time. Anywhere else Halon decides alone.
class CodeAgentPermissionService
  ALLOW_CONSEQUENCE = "It takes the step and carries on with the change.".freeze
  STOP_CONSEQUENCE = "The step is refused and the coding agent is told why. A repeated step ends the coding agent's run.".freeze
  UNDECIDED = "Halon could not decide, so the step was refused.".freeze

  # How long one request from the box waits for the decision before it says to ask again, under the time an HTTP
  # client in the box gives a call.
  WAIT_IN_CALL = 25
  POLL_EVERY = 1

  # The box's question about request_id, made once, with Halon set to decide it, and the decision once there is one,
  # waiting a little for it. events are the agent's latest events as the box printed them, read into plain lines the
  # way its step shows them. Answers the permission and OpenCode's reply, or nil while it waits.
  def self.ask!(session, request_id:, permission:, patterns:, metadata:, events:, hidden: [])
    steps = Integrations::SandboxAgentEvents.new(Chat::CodeFixProgress.start, hidden: hidden).read(Array(events).join("\n")).lines.map(&:text)
    asked, made = CodeAgentPermission.ask!(session, request_id: request_id, permission: permission, patterns: patterns, metadata: metadata, steps: steps)
    CodeAgentPermissionJob.perform_later(asked.id) if made
    [ asked, wait(asked) ]
  end

  def self.wait(permission)
    deadline = CodeAgent::QuestionTools.clock + WAIT_IN_CALL
    loop do
      reply = current(permission)
      return reply if reply || CodeAgent::QuestionTools.clock >= deadline

      CodeAgent::QuestionTools.pause(POLL_EVERY)
    end
  end
  private_class_method :wait

  def self.decide!(permission)
    return unless permission.open?

    session = permission.session
    decided = FirefightAi::PermissionJudge.new(permission.workspace, inferable: session).decide(
      asked: "The coding agent #{permission.asked}", steps: permission.steps, known: CodeAgentQuestionService.known(session.place),
      can_ask: session.place.present?
    )
    case decided.decision
    when FirefightAi::PermissionJudge::ALLOW then permission.decide!(allow: true, reason: decided.reason, by: SystemAgent.investigator)
    when FirefightAi::PermissionJudge::STOP then permission.decide!(allow: false, reason: decided.reason, by: SystemAgent.investigator)
    else ask_person!(permission, decided.reason, lean: decided.lean)
    end
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "code_permission.halon_did_not_decide", permission_id: permission.id, error: error.class.name }.to_json)
    permission.session.place ? ask_person!(permission, UNDECIDED, lean: nil) : permission.decide!(allow: false, reason: UNDECIDED, by: SystemAgent.investigator)
  end

  # The person is asked where the change was asked for, and nobody answering in time goes with the way Halon leaned, or
  # refuses the step when it could not lean.
  def self.ask_person!(permission, reason, lean:)
    recommended = { FirefightAi::PermissionJudge::ALLOW => CodeAgentPermission::OPTION_ALLOW,
                    FirefightAi::PermissionJudge::STOP => CodeAgentPermission::OPTION_STOP }[lean]
    question = CodeAgentQuestion.create!(
      session: permission.session, workspace: permission.workspace, permission: permission,
      question: CodeAgentQuestion.clean("The coding agent #{permission.asked}. Should it continue?", CodeAgentQuestion::QUESTION_LIMIT),
      options: [ { "label" => CodeAgentPermission::ALLOW, "consequence" => ALLOW_CONSEQUENCE },
                 { "label" => CodeAgentPermission::STOP, "consequence" => STOP_CONSEQUENCE } ],
      recommended: recommended, recommended_reason: (CodeAgentQuestion.clean(reason, CodeAgentQuestion::REASON_LIMIT) if recommended),
      answer_due_at: CodeAgentQuestion::ANSWER_WITHIN.from_now
    )
    CodeAgentQuestionJob.perform_later(question.id)
  end
  private_class_method :ask_person!

  # The decision once there is one, settling it from the person's question when that settled, or nil while it waits.
  # A question past its time is settled here too, since the box asks again until it hears.
  def self.current(permission)
    permission.reload
    if permission.open? && permission.question
      permission.question.expire_if_overdue!
      permission.settle_from_question!
    end
    permission.reply
  end
end

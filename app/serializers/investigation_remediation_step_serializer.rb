# One step of a fix, as the run page shows it.
class InvestigationRemediationStepSerializer < BaseSerializer
  object_as :step

  type :string
  def id = step.id

  type :number
  def position = step.position

  type "RemediationStepKind"
  def kind = step.kind

  type :string
  def description = step.description

  type :string, optional: true
  def repository = step.repository

  # The tool an action runs, as the workspace knows it, such as cloudflare.execute.
  type :string, optional: true
  def action = step.action_key

  type :string, optional: true
  def missing = step.missing

  type :string, optional: true
  def undo = step.undo

  type "number[]"
  def depends_on = step.depends_on

  type "RemediationStepStatus"
  def status = step.status

  # What a tool step sends, shown before anyone applies it, since it runs as them. Written by the agent and checked for
  # anything that looks like a credential when the fix was written.
  type :string, optional: true
  def arguments = (JSON.pretty_generate(step.arguments) if step.action? && step.arguments.present?)

  # Whether Firefight runs it when the fix is applied, an action or a code change it can open, rather than a person.
  type :boolean
  def runs_itself = step.runs_itself?

  # What the tool said back, another system's words, rendered as text.
  type :string, optional: true
  def result = step.result

  # What its coding agent has done so far, or did, the same shape a chat step carries.
  type "#{AgentChatMessageSerializer::PROGRESS_TYPE} | null"
  def progress = step.work&.to_h

  # Why whoever is looking cannot answer the coding agent's open question, or nil.
  type :string, optional: true
  def question_blocked_reason
    work = step.work
    return unless work&.waiting_for_answer?

    CodeAgentQuestion.find_by(id: work.question["id"])&.answer_blocked_reason(Current.principal)
  end

  type :string, optional: true
  def done_by = step.done_by&.display_name

  type :string, optional: true
  def mark_done_blocked_reason = step.mark_done_blocked_reason

  # Once approved, who approved it and how things stand now, as Halon read them before anyone runs it.
  type :string, optional: true
  def approved_by = (step.approval&.approver&.actor_display_name if step.approved?)

  type :boolean
  def checking = step.checking?

  type :boolean
  def lapsed = step.lapsed?

  type :string, optional: true
  def state = step.report&.state

  type :string, optional: true
  def warning = step.report&.warning

  type :string, optional: true
  def expires_at = (step.approval&.run_expires_at&.iso8601 if step.approved?)

  # What may be done with an approved step, each shown with why it is blocked for whoever is looking, who is the
  # request's principal.
  type "string[]"
  def offers = step.offers

  type :string, optional: true
  def run_blocked_reason = (step.run_blocked_reason(Current.principal) if step.offers.include?(Chat::CurrentState::ACTION_RUN))

  type :string, optional: true
  def dismiss_blocked_reason = (step.dismiss_blocked_reason(Current.principal) if step.offers.include?(Chat::CurrentState::ACTION_DISMISS))

  type :string, optional: true
  def ask_again_blocked_reason = (step.ask_again_blocked_reason(Current.principal) if step.offers.include?(Chat::CurrentState::ACTION_ASK_AGAIN))

  # The ledger row written before the call, whose decision is what let it run.
  type "{ decision: string, at: string } | null"
  def receipt
    step.invocation && { decision: step.invocation.decision, at: step.invocation.created_at.utc.iso8601 }
  end
end

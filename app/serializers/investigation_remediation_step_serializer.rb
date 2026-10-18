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

  # The tool an action runs, as the workspace knows it, such as cloudflare.execute or invite_responders, or the address a
  # page check opens.
  type :string, optional: true
  def action
    return step.arguments.to_h["url"] if step.page_check?

    step.firefight_tool? ? step.tool_name : step.action_key
  end

  type :string, optional: true
  def missing = step.missing

  type :string, optional: true
  def undo = step.undo

  type "number[]"
  def depends_on = step.depends_on

  type "RemediationStepStatus"
  def status = step.status

  # The same words Slack's fix message uses.
  type :string, optional: true
  def status_label = step.status_label

  # What a tool step sends, shown before anyone applies it, since it runs as them. Written by the agent and checked for
  # anything that looks like a credential when the fix was written.
  type :string, optional: true
  def arguments = (JSON.pretty_generate(step.arguments) if (step.action? || step.page_check?) && step.arguments.present?)

  # Whether Firefight runs it when the fix is applied, an action or a code change it can open, rather than a person.
  type :boolean
  def runs_itself = step.runs_itself?

  # What the tool said back, another system's words, rendered as text.
  type :string, optional: true
  def result = step.result

  # Why a person must look at what the step changed before anyone merges it, the same words Slack's fix message uses.
  type :string, optional: true
  def needs_person = step.needs_person

  # What its coding agent has done so far, or did, the same shape a chat step carries.
  type "#{AgentChatMessageSerializer::PROGRESS_TYPE} | null"
  def progress = work&.to_h

  # Why whoever is looking cannot continue or stop the change paused at its spending limit, or nil.
  type :string, optional: true
  def pause_blocked_reason
    work.pause_blocked_reason(step.workspace_id, Current.principal) if work&.pause
  end

  # Why whoever is looking cannot answer the coding agent's open question, or nil.
  type :string, optional: true
  def question_blocked_reason
    work.question_blocked_reason(step.workspace_id, Current.principal) if work&.waiting_for_answer?
  end

  # Why whoever is looking cannot change the answer to the coding agent's settled question, or nil.
  type :string, optional: true
  def question_change_blocked_reason = work&.question_change_blocked_reason(step.workspace_id, Current.principal)

  type :string, optional: true
  def done_by = step.done_by&.display_name

  type :string, optional: true
  def mark_done_blocked_reason = step.mark_done_blocked_reason

  # A step only a person can do, said as theirs, the same words Slack's checklist uses.
  type :string
  def your_step_line = step.your_step_line

  # Why a step that went through was already done, such as "Already done: Uros Nikolic is already in #inc-003", or nil.
  type :string, optional: true
  def already_done_line = (step.result_line if step.already_done_reason.present?)

  # What a step that went through produced, as words and the link they lead to, such as "Opened a pull request" and PR #856.
  type "{ lead: string, label: string, url: string } | null"
  def outcome
    return nil if step.already_done_reason.present? || step.outcome_url.blank?

    { lead: step.result_lead, label: step.outcome_label, url: step.outcome_url }
  end

  # Whether a failed step offers Try again, and why whoever is looking cannot press it, or nil.
  type :boolean
  def retry_offered = step.retry_offered?

  type :string, optional: true
  def retry_blocked_reason = (step.retry_blocked_reason(Current.principal) if retry_offered)

  # Why a failed or declined step did not go through, in the plain words Slack's checklist uses.
  type :string, optional: true
  def failure_line = step.failure_line

  # Once approved, who approved it and how things stand now, as Halon read them before anyone runs it.
  type :string, optional: true
  def approved_by = (step.approval&.approver&.actor_display_name if step.approved?)

  type :boolean
  def checking = step.checking?

  type :boolean
  def lapsed = step.lapsed?

  # What the step says once its approval ran out, worded from the approval's run window.
  type :string, optional: true
  def lapsed_reason = step.lapsed_reason

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

  private

  # The work as the step kept it, with its question as it stands now.
  def work = memo.fetch(:work) { step.shown_work }
end

# What one step of a run did, as the run's view on the canvas shows it: its state and time, what it is doing now, its log
# (every gateway call it made with how each was decided and ended, each tool Halon called for it, what a watch it keeps
# said and saw), the watch itself, what it was given and gave, the results it kept whole, its error, and why it cannot be
# tried again, skipped or started again from.
class WorkflowRunStepSerializer < BaseSerializer
  object_as :step

  ASK_QUESTION = "question".freeze
  ASK_APPROVAL = "approval".freeze
  ASK_TASK = "task".freeze
  ASK_KINDS = [ ASK_QUESTION, ASK_APPROVAL, ASK_TASK ].freeze
  ASK_TYPE = "{ kind: #{ASK_KINDS.map(&:inspect).join(' | ')}; id: string; question: string; details: string | null; " \
             "status: string; choices: { value: string; label: string }[]; fields: { name: string; label: string }[]; who: string; " \
             "blockedReason: string | null; answered: string | null; answeredBy: string | null }".freeze

  type :string
  def id
    step.id
  end

  type :string
  def step_key
    step.step_key
  end

  # The item's place in each for each it sits in, empty for a step at the top.
  type :string
  def iteration
    step.iteration
  end

  type "#{Workflow::Run::Step::STATUSES.map(&:inspect).join(' | ')}"
  def status
    step.status
  end

  type :string, optional: true
  def route
    step.route
  end

  type "Record<string, unknown>", optional: true
  def input
    step.input
  end

  type "Record<string, unknown>", optional: true
  def output
    step.output
  end

  # Why it skipped itself, such as a change whose problem cleared before it ran.
  type :string, optional: true
  def note
    step.note
  end

  # How long it used the run's sandbox, and what that time cost at its box's price.
  type :number
  def sandbox_seconds
    step.sandbox_seconds
  end

  type :number
  def sandbox_micros
    step.sandbox_micros
  end

  type "{ id: string; handle: string; bytes: number | null }[]"
  def saved_results
    step.saved_results.map { |result| { id: result.id, handle: result.handle, bytes: result.content&.bytesize } }
  end

  # The pages a Browser step saw, one per screen size, each served from the run's view.
  type "{ id: string; caption: string; url: string }[]"
  def screenshots
    shots = step.chat&.screenshots&.in_order.to_a
    shots.map do |shot|
      { id: shot.id, caption: shot.caption,
        url: Rails.application.routes.url_helpers.workflow_run_screenshot_path(step.run.workflow_id, step.run_id, shot) }
    end
  end

  type :number
  def attempts
    step.attempts
  end

  type :string, optional: true
  def error
    step.error
  end

  type :string, optional: true
  def started_at
    step.started_at&.iso8601
  end

  type :string, optional: true
  def finished_at
    step.finished_at&.iso8601
  end

  # An output pinned on the draft or kept from the run it started again from stood in, so the step did not run.
  type :boolean
  def stood_in
    step.top_level? && step.run.stood_in?(step.step_key)
  end

  # A change a test run only showed rather than made (DefinedWorkflow::Steps::Base#simulated_output).
  type :boolean
  def simulated
    step.output.to_h[DefinedWorkflow::Steps::Base::OUTPUT_SIMULATED] == true
  end

  type :boolean
  def waiting_approval
    activity.waiting_approval?(step)
  end

  # What it is doing right now in one line while it goes, such as the call it waits on or where a watch stands. Null
  # once it ended.
  type :string, optional: true
  def now
    activity.now_for(step)
  end

  LOG_TYPE = "{ id: string; at: string; until: string | null; count: number; text: string; detail: string | null; " \
             "tone: #{Workflow::Run::Activity::TONES.map(&:inspect).join(' | ')} }[]".freeze
  WATCH_TYPE = "{ active: boolean; headline: string; reads: string; basis: string; checkedAt: string | null; nextCheckAt: string | null; " \
               "expiresAt: string; steps: { id: string; label: string; status: #{Chat::Watch::Step::STATUSES.map(&:inspect).join(' | ')}; " \
               "line: string | null; url: string | null; readAt: string | null; lastSeen: string | null }[] }".freeze

  # Everything it did in the order it happened: its gateway calls, the tools Halon called for it and what a watch it
  # keeps said and saw, the same while it goes and afterwards.
  type LOG_TYPE
  def log
    activity.log_for(step)
  end

  # The watch a Watch step keeps: what it follows and how each stands, how often it read, when it reads next and when it
  # gives up. Null for any other step.
  type WATCH_TYPE, optional: true
  def watch
    activity.watching_for(step)
  end

  # What an Ask a person, Approval or Manual step asked people, with whether the person looking may answer it from here.
  type ASK_TYPE, optional: true
  def ask
    case step.kind
    when DefinedWorkflow::Steps::AskPerson.kind, DefinedWorkflow::Steps::Manual.kind then question_ask(step.asked_question)
    when DefinedWorkflow::Steps::Approval.kind then approval_ask(step.asked_approval)
    end
  end

  type :string, optional: true
  def retry_blocked_reason
    step.retry_blocked_reason
  end

  type :string, optional: true
  def skip_blocked_reason
    step.skip_blocked_reason
  end

  type :string, optional: true
  def rerun_blocked_reason
    step.rerun_blocked_reason
  end

  private

  def member = options[:member]

  def activity
    run = step.run
    run.activity(describe_tool: ->(name, arguments) { Chat::Tools.step(name, arguments, workspace: run.workspace) })
  end

  def question_ask(question)
    return unless question

    { kind: question.task? ? ASK_TASK : ASK_QUESTION, id: question.id, question: question.question, details: question.details, status: question.status,
      choices: question.choice_keys.map { |key| { value: key, label: question.choice_words(key) } },
      fields: question.fields.map { |field| { name: field[Workflow::Run::Question::FIELD_NAME], label: field[Workflow::Run::Question::FIELD_LABEL] } },
      who: question.asked_words, blockedReason: question.answer_blocked_reason(member),
      answered: question.answer_words, answeredBy: question.answered_by&.actor_display_name }
  end

  # While it waits, whether the gateway lets this person decide comes first, as pressing would answer, then the request's
  # own rules, such as it being decided already.
  def approval_blocked_reason(approval)
    return "Sign in to decide." unless member
    return approval.decide_blocked_reason(member) unless approval.pending?

    approval.decide_denied_reason(member) || approval.decide_blocked_reason(member)
  end

  def approval_ask(approval)
    return unless approval

    who = approval.named_approvers? ? approval.approvers.map(&:actor_display_name).to_sentence : "Any workspace #{approval.required_role}"
    { kind: ASK_APPROVAL, id: approval.id, question: approval.question.to_s, details: approval.question_details, status: approval.status,
      choices: [], fields: [], who: who, blockedReason: approval_blocked_reason(approval),
      answered: (approval.status unless approval.pending?), answeredBy: approval.approver&.actor_display_name }
  end
end

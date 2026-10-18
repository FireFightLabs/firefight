class Investigation < ApplicationRecord
  include Investigation::Seeding
  include Investigation::Citing
  include Investigation::Timeline
  include Investigation::Noting
  include Incident::LiveSignal

  # The incident page shows only whether a run is working on it. Its lease is renewed every turn.
  shown_on_incident_page Incident::LiveSignal::PART_INVESTIGATION,
                         if: -> { previously_new_record? || saved_change_to_status? || saved_change_to_subject_id? }

  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUS_CANCELED = "canceled"
  STATUSES = [
    STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELED
  ].freeze

  LIVE_STATUSES = [ STATUS_PENDING, STATUS_RUNNING ].freeze

  # Opens a run over the page of what it is about, since a run is read where it was asked for.
  QUERY_PARAM = "investigation"

  # The plain sentences a run stops with, the only ones people are shown. Anything else in error_summary is a technical
  # cause kept for whoever debugs it.
  STOPPED_BY_A_RESPONDER = "Stopped by a responder".freeze
  BUDGET_SPENT = "Budget spent before it could answer".freeze
  TOO_MANY_TURNS = "Stopped after too many turns".freeze
  STALLED = "Stopped talking without an answer".freeze
  REPEATED_CALL = "Repeated the same tool call".freeze
  ENDED_WITHOUT_AN_ANSWER = "Ended without an answer".freeze
  GAVE_UP = "Something went wrong on my side".freeze
  OUT_OF_TIME = "Stopped at its time limit before it could answer".freeze
  PLAIN_STOP_REASONS = [
    STOPPED_BY_A_RESPONDER, BUDGET_SPENT, TOO_MANY_TURNS, STALLED, REPEATED_CALL, ENDED_WITHOUT_AN_ANSWER, GAVE_UP, OUT_OF_TIME
  ].freeze

  # A worker renews this every turn, so a dead one holds the run for at most this long.
  LEASE = 5.minutes
  # A run taken this many times keeps losing its worker, and may be what is killing it.
  MAX_ATTEMPTS = 5
  # A run this old with no worker lost its job on the way to the queue.
  UNCLAIMED_AFTER = 2.minutes

  TRIGGER_COMMAND = "command"
  TRIGGER_BUTTON = "button"
  TRIGGER_CONVERSATION = "conversation"
  TRIGGER_MCP = "mcp"
  # The Investigate button on an incident's page.
  TRIGGER_DASHBOARD = "dashboard"
  # Started to measure Halon, and seen by nobody in the workspace. See Investigation::Rehearsal.
  TRIGGER_REHEARSAL = "rehearsal"
  # An alert opened the incident and nobody asked, so nobody may be watching (Investigation::AlertStart).
  TRIGGER_ALERT = "alert"
  # A check the workspace set to run on a schedule (Investigation::Check), which nobody asked for this time.
  TRIGGER_SCHEDULE = "schedule"
  # Something a connected provider reported that the security module looks into, such as a leaked secret.
  TRIGGER_SECURITY_EVENT = "security_event"
  # A workflow's Investigate step, which waits for what it finds.
  TRIGGER_WORKFLOW = "workflow"
  TRIGGER_SOURCES = [
    TRIGGER_COMMAND, TRIGGER_BUTTON, TRIGGER_CONVERSATION, TRIGGER_MCP, TRIGGER_DASHBOARD, TRIGGER_REHEARSAL, TRIGGER_ALERT, TRIGGER_SCHEDULE,
    TRIGGER_SECURITY_EVENT, TRIGGER_WORKFLOW
  ].freeze

  belongs_to :workspace
  # What the run is about. None for a question asked before anyone declared an incident, which is answered where it
  # was asked and can be tied to an incident declared from its answer.
  belongs_to :subject, polymorphic: true, optional: true
  # The chat that asked for it, which the answer goes back to.
  belongs_to :conversation, optional: true
  # Polymorphic because a person, an agent or a key can ask.
  belongs_to :triggered_by, polymorphic: true, optional: true
  # A replay answers every tool call from this run's record instead of reaching anything.
  belongs_to :replay_of, class_name: "Investigation", optional: true

  # Destroyed in declaration order, so the rows holding a hypothesis id go first.
  has_one :finding, class_name: "Investigation::Finding", dependent: :destroy
  has_many :steps, -> { ordered }, class_name: "Investigation::Step",
           dependent: :destroy, inverse_of: :investigation
  has_many :hypotheses, -> { ordered }, class_name: "Investigation::Hypothesis",
           dependent: :destroy, inverse_of: :investigation
  # Handbook edits Halon proposed while running. They outlive the run on the Handbook page.
  has_many :handbook_proposals, class_name: "Chat::HandbookProposal", dependent: :nullify
  has_one :chat, as: :owner, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :max_duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :asks_something

  scope :live, -> { where(status: LIVE_STATUSES) }
  # The runs people see. A rehearsal is not one, wherever runs are listed, read back or learned from.
  scope :seen, -> { where(rehearsal: false) }
  # Live with nobody working on it, which holds the subject's only slot until someone takes it. A rehearsal runs in
  # the process that started it, so no worker is owed it.
  scope :abandoned, -> {
    live.seen.where(
      "lease_until < :now OR (lease_until IS NULL AND investigations.created_at < :unclaimed)",
      now: Time.current, unclaimed: UNCLAIMED_AFTER.ago
    )
  }

  MODEL_NOT_SET_UP = "The AI model is not fully set up yet. An admin needs to finish setting it up.".freeze

  def self.unavailable_reason(workspace)
    return "AI features are not available." unless defined?(FirefightAi)

    gate = Entitlements.check(workspace, Entitlements::AI)
    return gate.message if gate.blocked?

    unknown_window_reason(workspace)
  end

  # The agent makes room from how full the model's window is, so a model with no known window does
  # not run. The operator is told which model, the person only that setup is not finished.
  def self.unknown_window_reason(workspace)
    choice = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace)
    model = choice.model
    return nil if FirefightAi.context_window(model, provider: choice.provider)

    Rails.logger.warn({ event: "ai.model_without_context_window", model: model, workspace_id: workspace.id }.to_json)
    MODEL_NOT_SET_UP
  end

  def self.available_for?(workspace)
    unavailable_reason(workspace).nil?
  end

  # The run a thread belongs to while it works, which is where a responder's note goes.
  def self.live_in_thread(workspace, thread_id)
    workspace.investigations.live.seen.find_by(thread_id: thread_id)
  end

  # The run a thread belongs to, finished or not. A reply there once it finished is a chat about what it found.
  def self.posted_in_thread(workspace, thread_id)
    workspace.investigations.seen.find_by(thread_id: thread_id)
  end

  # Every way in asks this, so a refusal reads the same from the command, the button, the chat and MCP.
  def self.start_refusal(workspace, incident = nil)
    unavailable_reason(workspace) || incident&.investigation_blocked_reason
  end

  def started_by_alert? = trigger_source == TRIGGER_ALERT

  # Raised when a run names someone to page who cannot be paged, with words the agent can act on.
  class PageRefused < StandardError; end

  # Who a run found on call and how to page them: the member, when they are one, their email as the tool gave it, and
  # the connection and target to raise the page on when an on-call tool is connected.
  PageAsk = Data.define(:member, :email, :integration, :target)

  def self.already_running_message(subject)
    "Already investigating #{subject.identifier}, I will post here when I have something."
  end

  NEEDS_A_QUESTION = "Say what is wrong, for example: investigate checkout returns 500 since 14:00.".freeze

  # The ledger wants an incident id. A subject that is not an incident has none.
  def incident
    subject if subject.is_a?(Incident)
  end

  def incident_id
    subject_id if subject_type == Incident.name
  end

  # The scheduled check a run is, when it is one.
  def check
    subject if subject.is_a?(Investigation::Check)
  end

  # A scheduled check looks for problems and says each through Investigation::Notice, rather than answering a question.
  def scheduled? = subject_type == Investigation::Check.name

  # A run on an incident speaks in the incident's channel. A question asked in a channel is answered there.
  def channel_id
    incident ? incident.channel_id : super
  end

  # What whoever asked said was wrong. A run with no incident is named by it.
  def question
    brief&.dig(Investigation::Brief::KEY_SYMPTOM)
  end

  # A run asked for in the chat platform, by its command or by mentioning Halon, holds the question in the platform's own
  # markup, as it does every note written there. Pages and posts show both as the platform reads them.
  def question_in_platform_markup? = brief&.dig(Investigation::Brief::KEY_SOURCE) == Investigation::Brief::SOURCE_COMMAND

  # The question as the run reads it, with people and channels named and their ids kept when it was asked in the chat
  # platform.
  def question_for_model = brief&.dig(Investigation::Brief::KEY_SYMPTOM_FOR_MODEL) || question

  # The brief the run is handed, its symptom as the run reads it.
  def brief_for_model
    read = brief&.dig(Investigation::Brief::KEY_SYMPTOM_FOR_MODEL)
    return brief unless read

    brief.except(Investigation::Brief::KEY_SYMPTOM_FOR_MODEL).merge(Investigation::Brief::KEY_SYMPTOM => read)
  end

  def said_in_platform
    [ (question if question_in_platform_markup?), *notes.select(&:from_platform).map { |note| note.as_written || note.content } ].compact
  end

  # Named by its incident, or by its question when it has no incident.
  def label
    return "#{incident.identifier} #{incident.name}" if incident
    return check.name if check

    question.to_s
  end

  # Ties a run asked without an incident to the one declared from its answer. Only once, and only from no incident.
  def attach_to!(incident)
    moved = self.class.where(id: id, subject_id: nil)
      .update_all(subject_type: Incident.name, subject_id: incident.id, updated_at: Time.current) > 0
    return false unless moved

    reload
    signal_incident_page
    note_started!
    note_answered!(finding) if finding
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Runs as the agent, not the person, so a finding does not depend on who asked. A run with a person, an agent or a key
  # behind it, whatever started it, reaches no further than they could themselves, by their own grants and their map
  # reach. Only a run nobody is behind, such as one an alert or a schedule started, or a workflow's own identity on a run
  # its trigger started, keeps the investigator's own reach. A starter whose row is gone is still someone, who reaches
  # nothing (Ability::GoneStarter), never the investigator's whole reach.
  def acting_principal
    agent = SystemAgent.investigator
    return agent.within_reach_of(check_owner) if scheduled? && triggered_by_type.blank?
    return agent if triggered_by_type.blank? || triggered_by_id.blank?

    starter = triggered_by || Ability::GoneStarter.new(type: triggered_by_type, id: triggered_by_id)
    workflows_own?(starter) ? agent : agent.within_reach_of(starter)
  end

  # A scheduled check's own runs are in its owner's name, someone who reaches nothing once they are gone.
  def check_owner = check.owner || Ability::GoneStarter.new(type: WorkspaceMembership.name, id: check.owner_id)

  def workflows_own?(starter) = starter.is_a?(Agent) && starter.workflow.present?

  def refusal(action_key)
    "Not allowed: this agent has no grant for #{action_key} in this workspace."
  end

  # A run acts as its own agent, so no person is refused and nobody is offered a pack.
  def pack_refused!(_action_key, _tool_call_id) = nil

  # Nobody is watching a run to confirm anything, so its reach is set by its grants and approval rules alone.
  def confirms?(_action, declared_destructive: false, **) = declared_destructive

  # A run has ended long before anyone approves a read it was held on, so nothing is kept to run later.
  def hold!(_approval, **) = false

  # A run investigates and never changes anything. A fix is applied by a person, so a tool that can write is offered
  # only when each call can be shown to read.
  def reads_only? = true

  # A rehearsal is measurement nobody in the workspace sees, so it reads memory and never saves, disputes or counts one.
  def changes_memory? = !rehearsal?

  # A run writes what it learned, and disputes what a result contradicted, as the agent, through the gateway, so an admin
  # who revokes the investigator's memory grant stops it and each change is in the activity log. No approval rule holds
  # it, as in a chat. It never vouches for a fact, and it is not a step of the run, since it checks nothing.
  def memory_change(crud_action, params:, tool_name:, &)
    Chat::ToolCall.run!(workspace: workspace, principal: acting_principal, params: params, context: ledger_context,
                        action_key: Ability::Action.system_key(Ability::Action::RESOURCE_MEMORY, crud_action), holdable: false, &)
  end

  # A search of the handbook's long pages, as the agent through the gateway, so it is in the activity log and an admin who
  # revokes the investigator's handbook grant stops it. A read is never held.
  def handbook_read(params:, tool_name:, &)
    Chat::ToolCall.run!(workspace: workspace, principal: acting_principal, params: params, context: ledger_context,
                        action_key: Ability::Action::HANDBOOK_READ, holdable: false, &)
  end

  # Where what the agent remembers came from. Nobody taught it, since a run acts as the agent.
  def memory_source = self

  def memory_teacher = nil

  def live?
    LIVE_STATUSES.include?(status)
  end

  def over?
    !live?
  end

  # Takes a waiting run, or a running one whose worker stopped renewing the lease. The queue only
  # hands a job out again once its worker is gone, so the job that holds the run takes it back at
  # once, while any other job waits out the lease, since the first worker may only be slow. The
  # start time and the count stay in SQL, so a caller holding a stale copy cannot move them.
  def claim!(by: nil)
    token = SecureRandom.uuid
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .where("lease_until IS NULL OR lease_until < :now OR lease_holder = :holder", now: Time.current, holder: by)
      .update_all(
        status: STATUS_RUNNING,
        lease_token: token,
        lease_holder: by,
        lease_until: LEASE.from_now,
        attempts: Arel.sql("attempts + 1"),
        started_at: Arel.sql("COALESCE(started_at, now())"),
        updated_at: Time.current
      ) > 0
    if moved
      @lease_token = token
      reload
    end
    moved
  end

  def worn_out? = attempts > MAX_ATTEMPTS

  # A run has no conversation to keep. Everything it has worked out is in its own records.
  def keeps_in_memory?(_message) = false

  # From the first turn to the last, or so far for a run still working.
  def duration_seconds
    return nil unless started_at

    ((completed_at || Time.current) - started_at).round
  end

  def spent_cents = (spent_micros / 10_000.0).round(2)

  # When the run has to conclude by, counted from its first turn so a run taken up again keeps its time. Nil for a run
  # from before time limits, or one not started.
  def deadline = (started_at + max_duration_seconds if started_at && max_duration_seconds)

  # Why a failed run stopped, in the words the thread was told. A technical cause is never shown to people, except that
  # the AI account ran out of credit, which is said without naming whose.
  def stopped_because
    return nil unless status == STATUS_FAILED
    return AiCredit.cannot(workspace).delete_suffix(".") if AiCredit.recorded?(error_summary)

    PLAIN_STOP_REASONS.include?(error_summary.to_s) ? error_summary : GAVE_UP
  end

  # The model a rehearsal was told to use, or nil for the workspace's own.
  def model_choice
    FirefightAi::ModelChoice.new(model: model_override, provider: provider_override.presence) if model_override.present?
  end

  # A run keeps its own chat with the model.
  def chat_owner = self

  CODE_BOX_PREFIX = "investigation-".freeze

  # Every tool that reads code in this run reads it in the same box.
  def code_box_key = "#{CODE_BOX_PREFIX}#{id}"

  # Where a run stands, from its own records, for a chat that is starting again with room to think.
  def memory_brief
    theories = hypotheses.includes(citations: :source).map do |theory|
      rests_on = theory.citations.filter_map { |citation| "step #{citation.source.position}" if citation.source.respond_to?(:position) }
      "- #{theory.assertion} (#{theory.status}#{", rests on #{rests_on.to_sentence}" if rests_on.any?})"
    end
    done = steps.where.not(position: nil).map { |step| "- step #{step.position}: #{step.label.presence || step.tool_name} (#{step.status})" }

    [
      "The facts Firefight already holds:\n#{JSON.pretty_generate(starting_facts)}",
      ("Your theories so far:\n#{theories.join("\n")}" if theories.any?),
      ("The steps you have taken:\n#{done.join("\n")}" if done.any?)
    ].compact.join("\n\n")
  end

  # The queue retries within seconds, so a worker that stumbles hands the run back rather than
  # leaving the retry to find it held. Only the holder can, so a worker that lost the run changes nothing.
  def release!
    return false if @lease_token.blank?

    moved = self.class.where(id: id, status: STATUS_RUNNING, lease_token: @lease_token)
      .update_all(lease_token: nil, lease_holder: nil, lease_until: nil, updated_at: Time.current) > 0
    @lease_token = nil if moved
    moved
  end

  # Writing the turn and holding the lease are one statement, so a worker that lost the run writes nothing.
  def ledger_context
    {
      source: AbilityGateway::SOURCE_INVESTIGATION,
      incident_id: incident_id,
      triggered_by_label: triggered_by.try(:actor_display_name)
    }
  end

  # Once per run, and the row decides, so a resumed run is not asked twice.
  def ask_for_critique!
    self.class.where(id: id, critique_asked_at: nil).update_all(critique_asked_at: Time.current, updated_at: Time.current) > 0
  end

  # Read from the row, since each turn's spend is written in SQL and never onto this copy.
  def budget_spent?
    spent, cap = self.class.where(id: id).pick(:spent_micros, :max_spend_cents)
    spent >= cap * FirefightAi::AgentLoop::MICROS_PER_CENT
  end

  def record_turn!(turns_used:, spent_micros:)
    return false if @lease_token.blank?

    self.class.where(id: id, status: STATUS_RUNNING, lease_token: @lease_token)
      .update_all(
        turns_used: turns_used, spent_micros: spent_micros,
        lease_until: LEASE.from_now, updated_at: Time.current
      ) > 0
  end

  # A step still running when the run is taken up belongs to a worker that died, since only the holder runs steps. It
  # ends saying so, rather than running on the run page forever.
  def close_interrupted_steps!
    now = Time.current
    steps.where(status: Investigation::Step::STATUS_RUNNING).update_all(
      status: Investigation::Step::STATUS_FAILED, error_summary: Chat::UnfinishedCalls::INTERRUPTED,
      failure_kind: Chat::StepOutcome::FAILURE_ERROR, completed_at: now, updated_at: now
    )
  end

  ALREADY_FINISHED = "This investigation has already finished.".freeze
  STOPPING = "Stopping. Halon ends the run now, even in the middle of a step.".freeze

  def stop_blocked_reason = (ALREADY_FINISHED unless live?)

  # The worker notices between turns, and RubyLLM stops a model call already in flight.
  def request_cancel!
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(cancel_requested: true, updated_at: Time.current) > 0
    chat&.cancel if moved
    moved
  end

  # The shared tools call this, so what a tool call leaves behind is the run's business. The step's
  # number travels back with the value, since it is what the agent cites the result by.
  # helper is the Chat::Helper making the call, when the run handed a check to one, which its step keeps.
  def tool_call(action_key:, params: {}, scope: {}, tool_name: nil, label: nil, holdable: true, helper: nil, **, &block)
    result = if replay_of_id
      Investigation::ToolCall.replay!(self, action_key: action_key, params: params, tool_name: tool_name, label: label, helper: helper)
    else
      Investigation::ToolCall.run!(self, action_key: action_key, params: params, scope: scope, tool_name: tool_name, label: label, holdable: holdable,
                                         helper: helper, &block)
    end
    Chat::ToolCall::Outcome.new(value: result.value, step: result.step.position)
  end

  # A run only reads, and its steps show no progress of their own.
  def progress_listener(_tool_call_id) = nil

  # A call that ran but whose answer said it failed. The step keeps what it answered and its status, so it can still be
  # cited, and the kind says how it is shown (Chat::StepOutcome).
  def mark_step_failed!(position, kind)
    steps.where(position: position).update_all(failure_kind: kind, updated_at: Time.current)
  end

  # A theory that is settled says which steps settled it, so a ruled out one carries its why.
  def record_hypothesis!(assertion:, status: nil, confidence: nil, steps: [])
    settled = [ Investigation::Hypothesis::STATUS_SUPPORTED, Investigation::Hypothesis::STATUS_REFUTED ].include?(status.to_s)
    cited = cited_steps!(steps, what: "This theory") if settled || Array(steps).any?

    transaction do
      hypothesis = hypotheses.find_or_initialize_by(assertion: assertion)
      hypothesis.position ||= (hypotheses.maximum(:position) || 0) + 1
      hypothesis.status = status if status.present?
      hypothesis.confidence = confidence unless confidence.nil?
      hypothesis.save!
      hypothesis.cite!(cited) if cited
      hypothesis
    end
  end

  # Each line of evidence is a claim and the steps it rests on. One that cites nothing real is
  # refused and nothing is written, so the agent fixes it before the run can end.
  # A run with no incident may say one is due, which its answer then offers to declare. A run on an incident has one.
  # A cause comes with how to fix it, whether or not anything here can apply it.
  # short is the answer in plain words for a channel (Investigation::Finding: answer_kind, confidence, what_is_wrong,
  # suggested_fix, not_checked), beside the full summary and gaps. Each evidence item may carry its claim in plain words.
  def conclude!(summary:, hypothesis_assertion: nil, evidence: [], gaps: nil, suggest_incident: false, fix: nil, page: nil, short: {})
    winner = hypotheses.find_by(assertion: hypothesis_assertion) if hypothesis_assertion.present?
    items = Array(evidence).map(&:to_h).map(&:symbolize_keys)
    raise Investigation::Evidence::Refused, "Naming a cause needs evidence behind it. Give each claim and the steps it rests on." if winner && items.empty?
    raise Investigation::RemediationPlan::Refused, "Naming a cause needs a fix. Say how to fix it, step by step." if winner && fix.blank?

    cited = items.each_with_index.map do |item, index|
      [ item[:claim].to_s, item[:plain].presence, cited_steps!(item[:steps], what: "Evidence #{index + 1}") ]
    end

    transaction do
      finding = create_finding!(summary: summary, winning_hypothesis: winner, gaps: gaps, suggests_incident: subject.nil? && suggest_incident == true,
                                page_member: page&.member, page_email: page&.email, page_integration: page&.integration, page_target: page&.target,
                                **short.to_h.symbolize_keys.slice(:answer_kind, :confidence, :what_is_wrong, :suggested_fix, :not_checked))
      cited.each_with_index { |(claim, plain, sources), index| finding.add_evidence!(claim: claim, plain: plain, sources: sources, position: index + 1) }
      Investigation::RemediationPlan.propose!(finding, fix) if fix.present?
      finding
    end
  end

  # Who the run names as on call, checked before anything is recorded: only in a run an alert started on an incident,
  # when the team lets Halon page, a member of this workspace, shown by steps the run took.
  # With an on-call tool connected the page is raised there, on the target the run names, and the person need not be a
  # member. Without one, or when Firefight cannot page through it, the incident is escalated to them, so they must be.
  def page_to(page)
    page = page.to_h.stringify_keys
    raise PageRefused, "Leave page out. Halon pages only in a run an alert started, when the team turned paging on." unless pages_on_call?

    email = page["person"].to_s.strip
    cited_steps!(page["steps"], what: "Page") unless on_call_in_facts?(email)
    member = workspace.workspace_memberships.resolve(email)
    integration = paging_tool(page["tool"])
    if integration
      target = page["target"].to_s.strip
      raise PageRefused, "Give target, what to page in #{integration.display_name}: #{Integrations::Paging.target_words(integration.provider)}." if target.empty?

      return PageAsk.new(member: member, email: email, integration: integration, target: target)
    end

    member || raise(PageRefused, "page names #{page['person'].inspect}, who is not a member of this workspace. Give the email of a member the " \
                                 "on-call tool named, or leave page out and say who in your answer.")
    PageAsk.new(member: member, email: email, integration: nil, target: nil)
  rescue Investigation::Evidence::Refused => refused
    raise PageRefused, refused.message
  end

  # Whether the facts the run started from say the person is on call now, which shows it as well as a step would.
  def on_call_in_facts?(email)
    return false if email.blank?

    tools = Array(seed_pack.to_h.dig(Investigation::Seeding::KEY_ON_CALL, "paging_tools"))
    tools.flat_map { |tool| Array(tool["on_call_now"]) }.any? { |person| person["email"].to_s.casecmp?(email) }
  end

  # The on-call tool a page goes through, by the name the facts give it, or the only one Firefight can page through.
  # nil when none can, so the page is an escalation here.
  def paging_tool(named)
    usable = Integrations::Paging.connections(workspace).select { |integration| workspace.paging_blocked_reason(integration).nil? }
    return nil if usable.empty?

    workspace.paging_connection(named, among: usable) ||
      raise(PageRefused, "Give tool, the on-call tool to page through: #{usable.map(&:slug).to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}.")
  end

  def pages_on_call? = started_by_alert? && incident.present? && workspace.on_call_paging_enabled?

  # Firefight paging someone on Halon's word is a call nobody asked for, so it is in the activity log as Halon's.
  def record_paging!(member, &)
    AbilityGateway.record_unattended!(
      principal: acting_principal, workspace: workspace, params: { "escalated_to" => member.id },
      action_key: Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE),
      context: { source: AbilityGateway::SOURCE_INVESTIGATION, incident_id: incident.id,
                 triggered_by_label: "Paging whoever is on call for #{incident.identifier}" }, &
    )
  end

  def finish!(status:, error_summary: nil)
    raise ArgumentError, "#{status} is not a terminal status" if LIVE_STATUSES.include?(status)

    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(
        status: status, error_summary: error_summary, completed_at: Time.current, updated_at: Time.current
      ) > 0
    reload if moved
    if moved
      signal_incident_page
      tell_workflows!
      ActiveRecord.after_all_transactions_commit { WorkflowSignalJob.perform_later(finished_signal) } if trigger_source == TRIGGER_WORKFLOW
    end
    moved
  end

  # What a workflow step waiting for this run to finish waits on.
  def finished_signal = "investigation.finished:#{id}"

  # A run that concluded or gave up is heard by the workspace's workflows once. One a person stopped, and a rehearsal,
  # are not.
  def tell_workflows!
    return if rehearsal? || status == STATUS_CANCELED

    Workflow::Trigger::Events.fire!(workspace, Workflow::Trigger::KIND_INVESTIGATION_FINISHED, key: id, subject: self, actor: triggered_by)
  end

  private

  # A run holds its incident as its subject, so a move is read from there.
  def incident_page_id_before_save
    type_before = saved_changes.fetch("subject_type", [ subject_type ]).first
    id_before = saved_changes.fetch("subject_id", [ subject_id ]).first
    id_before if type_before == Incident.name && id_before != incident_id
  end

  def asks_something
    errors.add(:brief, "needs a question when there is no incident") if subject.nil? && question.blank?
  end
end

class Investigation < ApplicationRecord
  include Investigation::Seeding
  include Investigation::Citing
  include Investigation::Timeline
  include Investigation::Noting

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
  PLAIN_STOP_REASONS = [
    STOPPED_BY_A_RESPONDER, BUDGET_SPENT, TOO_MANY_TURNS, STALLED, REPEATED_CALL, ENDED_WITHOUT_AN_ANSWER, GAVE_UP
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
  # Started to measure Halon, and seen by nobody in the workspace. See Investigation::Rehearsal.
  TRIGGER_REHEARSAL = "rehearsal"
  TRIGGER_SOURCES = [ TRIGGER_COMMAND, TRIGGER_BUTTON, TRIGGER_CONVERSATION, TRIGGER_MCP, TRIGGER_REHEARSAL ].freeze

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
  has_one :chat, as: :owner, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }
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

  def self.unavailable_reason(workspace)
    return "AI features are not available." unless defined?(FirefightAi)
    return "Investigations are not turned on for this workspace." unless FeatureFlags.enabled?(workspace, FeatureFlags::AI_SRE)

    gate = Entitlements.check(workspace, Entitlements::AI)
    return gate.message if gate.blocked?

    unknown_window_reason(workspace)
  end

  # The agent makes room from how full the model's window is, so a model with no known window does
  # not run. The operator is told which model, the person only that setup is not finished.
  def self.unknown_window_reason(workspace)
    model = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace).model
    return nil if FirefightAi.context_window(model)

    Rails.logger.warn({ event: "ai.model_without_context_window", model: model, workspace_id: workspace.id }.to_json)
    "The AI model is not fully set up yet. An admin needs to finish setting it up."
  end

  def self.available_for?(workspace)
    unavailable_reason(workspace).nil?
  end

  # Every way in asks this, so a refusal reads the same from the command, the button, the chat and MCP.
  # The run a thread belongs to while it works, which is where a responder's note goes.
  def self.live_in_thread(workspace, thread_id)
    workspace.investigations.live.seen.find_by(thread_id: thread_id)
  end

  def self.start_refusal(workspace, incident = nil)
    unavailable_reason(workspace) || incident&.investigation_blocked_reason
  end

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

  # A run on an incident speaks in the incident's channel. A question asked in a channel is answered there.
  def channel_id
    incident ? incident.channel_id : super
  end

  # What whoever asked said was wrong. A run with no incident is named by it.
  def question
    brief&.dig(Investigation::Brief::KEY_SYMPTOM)
  end

  # Ties a run asked without an incident to the one declared from its answer. Only once, and only from no incident.
  def attach_to!(incident)
    moved = self.class.where(id: id, subject_id: nil)
      .update_all(subject_type: Incident.name, subject_id: incident.id, updated_at: Time.current) > 0
    return false unless moved

    reload
    note_started!
    note_answered!(finding) if finding
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Runs as the agent, not the person, so a finding does not depend on who asked.
  def acting_principal
    SystemAgent.investigator
  end

  def refusal(action_key)
    "Not allowed: this agent has no grant for #{action_key} in this workspace."
  end

  # Nobody is watching a run to confirm anything, so its reach is set by its grants and approval rules alone.
  def confirms?(_action) = false

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

  # Why a failed run stopped, in the words the thread was told. A technical cause is never shown to people.
  def stopped_because
    return nil unless status == STATUS_FAILED

    PLAIN_STOP_REASONS.include?(error_summary.to_s) ? error_summary : GAVE_UP
  end

  # The model a rehearsal was told to use, or nil for the workspace's own.
  def model_choice
    FirefightAi::ModelChoice.new(model: model_override, provider: provider_override.presence) if model_override.present?
  end

  # A run keeps its own chat with the model.
  def chat_owner = self

  # Every tool that reads code in this run reads it in the same box.
  def code_box_key = "investigation-#{id}"

  # Where a run stands, from its own records, for a chat that is starting again with room to think.
  def memory_brief
    theories = hypotheses.includes(citations: :source).map do |theory|
      rests_on = theory.citations.filter_map { |citation| "step #{citation.source.position}" if citation.source.respond_to?(:position) }
      "- #{theory.assertion} (#{theory.status}#{", rests on #{rests_on.to_sentence}" if rests_on.any?})"
    end
    done = steps.where.not(position: nil).map { |step| "- step #{step.position}: #{step.label.presence || step.tool_name} (#{step.status})" }

    [
      "The facts Firefight already holds:\n#{JSON.pretty_generate(seed_pack)}",
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
      triggered_by_label: triggered_by.try(:principal_label)
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

  # The worker notices between turns, and RubyLLM stops a model call already in flight.
  def request_cancel!
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(cancel_requested: true, updated_at: Time.current) > 0
    chat&.cancel if moved
    moved
  end

  # The shared tools call this, so what a tool call leaves behind is the run's business. The step's
  # number travels back with the value, since it is what the agent cites the result by.
  def tool_call(action_key:, params: {}, scope: {}, tool_name: nil, label: nil, **, &block)
    result = if replay_of_id
      Investigation::ToolCall.replay!(self, action_key: action_key, params: params, tool_name: tool_name, label: label)
    else
      Investigation::ToolCall.run!(self, action_key: action_key, params: params, scope: scope, tool_name: tool_name, label: label, &block)
    end
    Chat::ToolCall::Outcome.new(value: result.value, step: result.step.position)
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
  def conclude!(summary:, hypothesis_assertion: nil, evidence: [], gaps: nil, suggest_incident: false)
    winner = hypotheses.find_by(assertion: hypothesis_assertion) if hypothesis_assertion.present?
    items = Array(evidence).map(&:to_h).map(&:symbolize_keys)
    raise Investigation::Evidence::Refused, "Naming a cause needs evidence behind it. Give each claim and the steps it rests on." if winner && items.empty?

    cited = items.each_with_index.map { |item, index| [ item[:claim].to_s, cited_steps!(item[:steps], what: "Evidence #{index + 1}") ] }

    transaction do
      finding = create_finding!(summary: summary, winning_hypothesis: winner, gaps: gaps, suggests_incident: subject.nil? && suggest_incident == true)
      cited.each_with_index { |(claim, sources), index| finding.add_evidence!(claim: claim, sources: sources, position: index + 1) }
      finding
    end
  end

  def finish!(status:, error_summary: nil)
    raise ArgumentError, "#{status} is not a terminal status" if LIVE_STATUSES.include?(status)

    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(
        status: status, error_summary: error_summary, completed_at: Time.current, updated_at: Time.current
      ) > 0
    reload if moved
    moved
  end

  private

  def asks_something
    errors.add(:brief, "needs a question when there is no incident") if subject.nil? && question.blank?
  end
end

class Investigation < ApplicationRecord
  include Investigation::Seeding

  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUS_CANCELED = "canceled"
  STATUSES = [
    STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELED
  ].freeze

  LIVE_STATUSES = [ STATUS_PENDING, STATUS_RUNNING ].freeze

  # A worker renews this every turn, so a dead one holds the run for at most this long.
  LEASE = 5.minutes

  TRIGGER_COMMAND = "command"
  TRIGGER_BUTTON = "button"
  TRIGGER_CONVERSATION = "conversation"
  TRIGGER_SOURCES = [ TRIGGER_COMMAND, TRIGGER_BUTTON, TRIGGER_CONVERSATION ].freeze

  belongs_to :workspace
  # Polymorphic so a run can be about something other than an incident later.
  belongs_to :subject, polymorphic: true
  # Polymorphic because a person, an agent or a key can ask.
  belongs_to :triggered_by, polymorphic: true, optional: true

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

  scope :live, -> { where(status: LIVE_STATUSES) }

  def self.unavailable_reason(workspace)
    return "AI features are not available." unless defined?(FirefightAi)
    return "Investigations are not turned on for this workspace." unless FeatureFlags.enabled?(workspace, FeatureFlags::AI_SRE)

    gate = Entitlements.check(workspace, Entitlements::AI)
    return gate.message if gate.blocked?

    nil
  end

  def self.available_for?(workspace)
    unavailable_reason(workspace).nil?
  end

  # Whether this person may read what the agent writes. The nav, the chat page and its socket all ask
  # this, so none of them offers what the gateway would refuse.
  def self.readable_by?(member)
    return false unless member

    key = Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ)
    action = Ability::Action.lookup(key, member.workspace)
    action.present? && AbilityGateway.permitted?(member, action, key, member.workspace, {})
  end

  def self.already_running_message(subject)
    "Already investigating #{subject.identifier}, I will post here when I have something."
  end

  # The ledger wants an incident id. A subject that is not an incident has none.
  def incident
    subject if subject.is_a?(Incident)
  end

  def incident_id
    subject_id if subject_type == Incident.name
  end

  # Only an incident has a channel, so any other subject gets nil.
  def channel_id
    incident&.channel_id
  end

  # Runs as the agent, not the person, so a finding does not depend on who asked.
  def agent_principal
    SystemAgent.investigator
  end

  def live?
    LIVE_STATUSES.include?(status)
  end

  def over?
    !live?
  end

  # Takes a waiting run, or a running one whose worker stopped renewing the lease. The start time
  # is kept in SQL, so a caller holding a stale copy cannot move it.
  def claim!
    token = SecureRandom.uuid
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .where(lease_until: [ nil, ...Time.current ])
      .update_all(
        status: STATUS_RUNNING,
        lease_token: token,
        lease_until: LEASE.from_now,
        started_at: Arel.sql("COALESCE(started_at, now())"),
        updated_at: Time.current
      ) > 0
    if moved
      @lease_token = token
      reload
    end
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

  def record_turn!(turns_used:, spent_cents:)
    return false if @lease_token.blank?

    self.class.where(id: id, status: STATUS_RUNNING, lease_token: @lease_token)
      .update_all(
        turns_used: turns_used, spent_cents: spent_cents,
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

  # The shared tools call this, so what a tool call leaves behind is the run's business.
  def tool_call(action_key:, params: {}, &block)
    Investigation::ToolCall.run!(self, action_key: action_key, params: params, &block).value
  end

  def record_hypothesis!(assertion:, status: nil, confidence: nil)
    hypothesis = hypotheses.find_or_initialize_by(assertion: assertion)
    hypothesis.position ||= (hypotheses.maximum(:position) || 0) + 1
    hypothesis.status = status if status.present?
    hypothesis.confidence = confidence unless confidence.nil?
    hypothesis.save!
    hypothesis
  end

  # Posting, confidence factors and citation checks come later.
  def conclude!(summary:, hypothesis_assertion: nil, evidence: [], gaps: nil)
    winner = hypotheses.find_by(assertion: hypothesis_assertion) if hypothesis_assertion.present?
    create_finding!(
      summary: summary, winning_hypothesis: winner, evidence: Array(evidence).map(&:to_s), gaps: gaps
    )
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
end

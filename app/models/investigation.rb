class Investigation < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUS_CANCELED = "canceled"
  # Out of budget, so it says what it has instead of going quiet.
  STATUS_CAPPED = "capped"
  STATUSES = [
    STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELED, STATUS_CAPPED
  ].freeze

  # A live run is the one a second request attaches to.
  LIVE_STATUSES = [ STATUS_PENDING, STATUS_RUNNING ].freeze

  TRIGGER_COMMAND = "slack_command"
  TRIGGER_BUTTON = "slack_button"
  TRIGGER_ALERT = "alert"
  TRIGGER_AGENT = "agent"
  TRIGGER_WORKFLOW = "workflow"
  TRIGGER_API = "api"
  TRIGGER_SOURCES = [
    TRIGGER_COMMAND, TRIGGER_BUTTON, TRIGGER_ALERT, TRIGGER_AGENT, TRIGGER_WORKFLOW, TRIGGER_API
  ].freeze

  belongs_to :workspace
  belongs_to :incident
  belongs_to :agent, optional: true
  # Polymorphic because a person, an agent or a key can ask.
  belongs_to :triggered_by, polymorphic: true, optional: true

  # Destroyed in declaration order, so the rows holding a hypothesis id go first.
  has_one :finding, dependent: :destroy
  has_many :investigation_steps, -> { ordered }, dependent: :destroy, inverse_of: :investigation
  has_many :hypotheses, -> { ordered }, dependent: :destroy, inverse_of: :investigation

  validates :status, inclusion: { in: STATUSES }
  validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }
  validates :max_turns, :max_tokens, numericality: { only_integer: true, greater_than: 0 }
  validates :confidence_threshold,
            numericality: { greater_than: 0, less_than_or_equal_to: 1 }

  scope :live, -> { where(status: LIVE_STATUSES) }
  scope :recent, -> { order(created_at: :desc) }

  # One sentence both entry points show, so neither re-derives the rule.
  def self.unavailable_reason(workspace)
    return "AI features are not available in this build." unless defined?(FirefightAi)

    unless FeatureFlags.enabled?(workspace, FeatureFlags::AI_SRE)
      return "Investigations are not turned on for this workspace yet."
    end

    gate = Entitlements.check(workspace, Entitlements::AI)
    gate.blocked? ? gate.message : nil
  end

  def self.available_for?(workspace)
    unavailable_reason(workspace).nil?
  end

  def live?
    LIVE_STATUSES.include?(status)
  end

  def over?
    !live?
  end

  # One guarded statement, so two workers cannot both run the same investigation.
  # The loser sees false and leaves it alone.
  def claim_running!
    moved = self.class.where(id: id, status: STATUS_PENDING)
      .update_all(status: STATUS_RUNNING, started_at: Time.current, updated_at: Time.current) > 0
    reload if moved
    moved
  end

  def finish!(status:, error_summary: nil)
    raise ArgumentError, "#{status} is not a terminal status" if LIVE_STATUSES.include?(status)

    # From either live status, so a run that failed before it was claimed still lands
    # somewhere terminal instead of sitting pending and blocking the next request.
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(
        status: status, error_summary: error_summary, completed_at: Time.current, updated_at: Time.current
      ) > 0
    reload if moved
    moved
  end

  def budget_spent?
    turns_used >= max_turns || tokens_used >= max_tokens
  end

  def next_step_position
    investigation_steps.maximum(:position).to_i + 1
  end
end

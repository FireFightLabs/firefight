class Investigation < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUS_CANCELED = "canceled"
  STATUSES = [
    STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELED
  ].freeze

  LIVE_STATUSES = [ STATUS_PENDING, STATUS_RUNNING ].freeze

  TRIGGER_COMMAND = "command"
  TRIGGER_BUTTON = "button"
  TRIGGER_SOURCES = [ TRIGGER_COMMAND, TRIGGER_BUTTON ].freeze

  belongs_to :workspace
  belongs_to :incident
  # Polymorphic because a person, an agent or a key can ask.
  belongs_to :triggered_by, polymorphic: true, optional: true

  # Destroyed in declaration order, so the rows holding a hypothesis id go first.
  has_one :finding, class_name: "Investigation::Finding", dependent: :destroy
  has_many :steps, -> { ordered }, class_name: "Investigation::Step",
           dependent: :destroy, inverse_of: :investigation
  has_many :hypotheses, -> { ordered }, class_name: "Investigation::Hypothesis",
           dependent: :destroy, inverse_of: :investigation

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

  def self.already_running_message(incident)
    "Already investigating #{incident.identifier}, I will post here when I have something."
  end

  def live?
    LIVE_STATUSES.include?(status)
  end

  def over?
    !live?
  end

  # Takes a waiting run, and picks up one that was already started, which is what
  # resuming after a killed worker means. False means the run is already over.
  # The start time is kept in SQL, so a caller holding a stale copy cannot move it.
  def claim!
    moved = self.class.where(id: id, status: LIVE_STATUSES)
      .update_all(
        status: STATUS_RUNNING,
        started_at: Arel.sql("COALESCE(started_at, now())"),
        updated_at: Time.current
      ) > 0
    reload if moved
    moved
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

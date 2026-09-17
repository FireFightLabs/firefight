class Investigation::Finding < ApplicationRecord
  include Investigation::Finding::Searchable
  STATE_UNPUBLISHED = "unpublished"
  STATE_PUBLISHED = "published"
  # Below the workspace's confidence bar, or holding instruction-like evidence.
  STATE_HELD = "held"
  STATES = [ STATE_UNPUBLISHED, STATE_PUBLISHED, STATE_HELD ].freeze

  OUTCOME_CONFIRMED = "confirmed"
  OUTCOME_PARTIAL = "partial"
  OUTCOME_WRONG = "wrong"
  OUTCOMES = [ OUTCOME_CONFIRMED, OUTCOME_PARTIAL, OUTCOME_WRONG ].freeze

  REMEDIATION_CODE_CHANGE = "code_change"
  REMEDIATION_DATA_CHANGE = "data_change"
  REMEDIATION_CONFIG_CHANGE = "config_change"
  REMEDIATION_TRANSIENT = "transient"
  REMEDIATION_ACTION = "action"
  REMEDIATION_TYPES = [
    REMEDIATION_CODE_CHANGE, REMEDIATION_DATA_CHANGE, REMEDIATION_CONFIG_CHANGE,
    REMEDIATION_TRANSIENT, REMEDIATION_ACTION
  ].freeze

  belongs_to :investigation
  belongs_to :winning_hypothesis, class_name: "Investigation::Hypothesis", optional: true
  belongs_to :outcome_by, polymorphic: true, optional: true
  scope :in_workspace, ->(workspace) {
    joins(:investigation).where(investigations: { workspace_id: workspace.id })
  }

  has_many :verdicts, class_name: "Investigation::Verdict", dependent: :destroy, inverse_of: :finding

  validates :published_state, inclusion: { in: STATES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :remediation_type, inclusion: { in: REMEDIATION_TYPES }, allow_nil: true
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  # Everyone who read the finding gets a say, and anyone may change their mind. The outcome the
  # record carries is what the room agreed, or nothing while the room is split.
  def record_verdict!(outcome, by:)
    verdict = verdicts.find_or_initialize_by(member: by)
    verdict.outcome = outcome
    verdict.save!
    settle_outcome!
    verdict
  end

  def tally
    verdicts.group(:outcome).count
  end

  private

  def settle_outcome!
    counts = tally
    agreed = counts.size == 1 ? counts.keys.first : nil
    update!(outcome: agreed, outcome_at: agreed ? Time.current : nil, outcome_by: nil)
  end
end

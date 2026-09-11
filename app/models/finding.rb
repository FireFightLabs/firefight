class Finding < ApplicationRecord
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
  belongs_to :winning_hypothesis, class_name: "Hypothesis", optional: true
  belongs_to :outcome_by, polymorphic: true, optional: true

  validates :published_state, inclusion: { in: STATES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :remediation_type, inclusion: { in: REMEDIATION_TYPES }, allow_nil: true
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  def published?
    published_state == STATE_PUBLISHED
  end

  def held?
    published_state == STATE_HELD
  end

  def grade!(outcome:, by:)
    update!(outcome: outcome, outcome_by: by, outcome_at: Time.current)
  end
end

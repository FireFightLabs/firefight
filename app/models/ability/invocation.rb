module Ability
  # Written before execution and finalized once after, so a nil completed_at means attempted
  # with the outcome unknown rather than erased by a crash. No result bodies are stored.
  class Invocation < ApplicationRecord
    DECISION_ALLOW = "allow"
    DECISION_DENY = "deny"
    DECISION_PENDING = "pending"
    DECISIONS = [ DECISION_ALLOW, DECISION_DENY, DECISION_PENDING ].freeze

    OUTCOME_SUCCESS = "success"
    OUTCOME_ERROR = "error"
    OUTCOMES = [ OUTCOME_SUCCESS, OUTCOME_ERROR ].freeze

    class AlreadyFinalized < StandardError; end

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true

    validates :principal_label, :action_key, :idempotency_key, presence: true
    validates :decision, inclusion: { in: DECISIONS }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true

    scope :pending_outcome, -> { where(decision: DECISION_ALLOW, completed_at: nil) }

    def finalize!(outcome:, error_summary: nil, duration_ms: nil)
      raise AlreadyFinalized, "invocation #{id} is already finalized" if completed_at.present?

      update!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms,
              completed_at: Time.current)
    end
  end
end

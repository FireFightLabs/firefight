module Ability
  # The write-ahead audit ledger. A row is written before execution with the
  # immutable decision facts. Outcome and completed_at are finalized exactly
  # once afterwards. completed_at: nil means "attempted, outcome unknown",
  # the signal a crash mid-execution would otherwise erase. No result bodies:
  # outputs live with the consumer, the ledger records that and how it ran.
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

    scope :pending_outcome, -> { where(decision: DECISION_ALLOW, completed_at: nil) }

    def finalize!(outcome:, error_summary: nil, duration_ms: nil)
      raise AlreadyFinalized, "invocation #{id} is already finalized" if completed_at.present?

      update!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms,
              completed_at: Time.current)
    end
  end
end

module Ability
  # Written before execution and finalized once after, so a nil completed_at means attempted
  # with the outcome unknown rather than erased by a crash. No result bodies are stored.
  class Invocation < ApplicationRecord
    include Ability::ConnectionNamed

    DECISION_ALLOW = "allow"
    DECISION_DENY = "deny"
    DECISION_PENDING = "pending"
    DECISIONS = [ DECISION_ALLOW, DECISION_DENY, DECISION_PENDING ].freeze

    OUTCOME_SUCCESS = "success"
    OUTCOME_ERROR = "error"
    # One of Firefight's own rules refused the call once it was allowed, such as a protected branch, so it did nothing.
    OUTCOME_REFUSED = "refused"
    OUTCOMES = [ OUTCOME_SUCCESS, OUTCOME_ERROR, OUTCOME_REFUSED ].freeze

    class AlreadyFinalized < StandardError; end

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true

    validates :principal_label, :action_key, :idempotency_key, presence: true
    validates :decision, inclusion: { in: DECISIONS }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true

    scope :pending_outcome, -> { where(decision: DECISION_ALLOW, completed_at: nil) }

    SUMMARY_LIMIT = 200
    ANSWERED_ERROR = "The tool answered with an error.".freeze

    # What a tool said when it answered with its own error, cut to the first line it said, with anything that looks
    # like a credential replaced, since the ledger keeps no result bodies and never a secret.
    def self.summary_of(text)
      said = text.to_s.lines.map(&:strip).find(&:present?)
      said ? Chat::SecretFree.redacted(said).truncate(SUMMARY_LIMIT) : ANSWERED_ERROR
    end

    def finalize!(outcome:, error_summary: nil, duration_ms: nil)
      raise AlreadyFinalized, "invocation #{id} is already finalized" if completed_at.present?

      update!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms,
              completed_at: Time.current)
    end
  end
end

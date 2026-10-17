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
    # The workflow run whose step made the call.
    belongs_to :workflow_run, class_name: "Workflow::Run", optional: true
    # The approval a held call waits on, or the one that let it through.
    belongs_to :approval, class_name: "Ability::Approval", optional: true
    # The entry of what Halon may do without asking that let a chat's change run without the person's yes.
    belongs_to :allowance, class_name: "Ability::Allowance", optional: true

    # Why a change Halon made in a chat ran without the person's yes, kept so the activity log says it.
    UNASKED_SAFE = "safe_change"
    UNASKED_ALLOWANCE = "allowance"
    UNASKED_REASONS = [ UNASKED_SAFE, UNASKED_ALLOWANCE ].freeze

    validates :principal_label, :action_key, :idempotency_key, presence: true
    validates :unasked_reason, inclusion: { in: UNASKED_REASONS }, allow_nil: true
    validates :decision, inclusion: { in: DECISIONS }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true

    scope :pending_outcome, -> { where(decision: DECISION_ALLOW, completed_at: nil) }
    # With what each row needs to say why it ran without asking (#unasked_because), read for a whole page at once.
    scope :with_allowances, -> { includes(allowance: [ :environment, :integration, { action: :source } ]) }

    # Why a change ran without the person's yes, in the words the activity log and the change's card both show, or nil.
    def self.unasked_words(reason, allowance)
      case reason
      when UNASKED_SAFE then "Made without asking because it is a safe change."
      when UNASKED_ALLOWANCE
        entry = allowance ? "\"#{allowance.sentence}\"" : "an entry that is gone now"
        "Made without asking because #{entry} is on the list of what Halon may do without asking."
      end
    end

    def unasked_because = self.class.unasked_words(unasked_reason, allowance)

    SUMMARY_LIMIT = 200
    ANSWERED_ERROR = "The tool answered with an error.".freeze

    # What a tool said when it answered with its own error, cut to the first line it said, with anything that looks
    # like a credential replaced, since the ledger keeps no result bodies and never a secret.
    def self.summary_of(text)
      said = text.to_s.lines.map(&:strip).find(&:present?)
      said ? Chat::SecretFree.redacted(said).truncate(SUMMARY_LIMIT) : ANSWERED_ERROR
    end

    def finished? = completed_at.present?

    def succeeded? = outcome == OUTCOME_SUCCESS

    def finalize!(outcome:, error_summary: nil, duration_ms: nil)
      raise AlreadyFinalized, "invocation #{id} is already finalized" if completed_at.present?

      update!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms,
              completed_at: Time.current)
    end
  end
end

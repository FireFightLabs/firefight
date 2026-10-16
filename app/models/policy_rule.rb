class PolicyRule < ApplicationRecord
  OPERATOR_IS_ONE_OF = "is_one_of"
  OPERATOR_CONTAINS = "contains"
  OPERATOR_STARTS_WITH = "starts_with"
  OPERATOR_MATCHES_REGEX = "matches_regex"
  OPERATOR_IS_EMPTY = "is_empty"
  OPERATORS = [
    OPERATOR_IS_ONE_OF, OPERATOR_CONTAINS, OPERATOR_STARTS_WITH,
    OPERATOR_MATCHES_REGEX, OPERATOR_IS_EMPTY
  ].freeze

  ARRAY_VALUE_OPERATORS = [ OPERATOR_IS_ONE_OF ].freeze
  STRING_VALUE_OPERATORS = [ OPERATOR_CONTAINS, OPERATOR_STARTS_WITH, OPERATOR_MATCHES_REGEX ].freeze
  VALUELESS_OPERATORS = [ OPERATOR_IS_EMPTY ].freeze
  # Comparisons of a number, such as a count above 20. A workflow's trigger offers them (Workflow::Trigger::CONDITION_OPERATORS),
  # and a routing rule keeps OPERATORS, whose fields are words.
  OPERATOR_GREATER_THAN = "greater_than"
  OPERATOR_LESS_THAN = "less_than"
  NUMBER_OPERATORS = [ OPERATOR_GREATER_THAN, OPERATOR_LESS_THAN ].freeze

  belongs_to :policy

  # Approval rules decide which calls wait for a person, so a token never changes them.
  TOKEN_CHANGE_REFUSAL = "Approval rules are changed only by a person in Firefight, never with a token, so no token can loosen the rules that hold its own calls.".freeze

  # Why changing an approval rule from this source is refused, or nil.
  def self.approval_change_blocked_reason(source) = (TOKEN_CHANGE_REFUSAL if AbilityGateway::TOKEN_SOURCES.include?(source))

  # Domains without a contract accept any object.
  OUTCOME_VALIDATORS = {
    Policy::DOMAIN_ALERT_ROUTING => PolicyRule::AlertRoutingOutcome,
    Policy::DOMAIN_APPROVALS => PolicyRule::ApprovalOutcome
  }.freeze

  validates :priority, presence: true, uniqueness: { scope: :policy_id }
  validate :conditions_are_well_formed
  validate :outcome_matches_domain_contract
  validate :approval_conditions_hold_changes, if: -> { policy&.domain == Policy::DOMAIN_APPROVALS && conditions_changed? }

  # Two steps through a temporary priority to satisfy the unique index. A
  # nil neighbour means the rule is already at that end.
  def swap_priority_with!(other)
    return unless other

    transaction do
      mine, theirs = priority, other.priority
      update_columns(priority: -1)
      other.update_columns(priority: mine)
      update_columns(priority: theirs)
    end
  end

  private

  def outcome_matches_domain_contract
    validator = OUTCOME_VALIDATORS[policy&.domain]
    return unless validator

    validator.errors_for(outcome, workspace: policy.workspace).each { |message| errors.add(:outcome, message) }
  end

  def approval_conditions_hold_changes
    PolicyRule::ApprovalConditions.errors_for(conditions, workspace: policy.workspace).each { |message| errors.add(:conditions, message) }
  end

  def conditions_are_well_formed
    Policy::Conditions.errors_for(conditions).each { |message| errors.add(:conditions, message) }
  end
end

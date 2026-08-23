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

  belongs_to :policy

  # Outcome contracts per policy domain. Domains without a contract accept any object.
  OUTCOME_VALIDATORS = {
    Policy::DOMAIN_ALERT_ROUTING => PolicyRule::AlertRoutingOutcome,
    Policy::DOMAIN_APPROVALS => PolicyRule::ApprovalOutcome
  }.freeze

  validates :priority, presence: true, uniqueness: { scope: :policy_id }
  validate :conditions_are_well_formed
  validate :outcome_matches_domain_contract

  private

  def outcome_matches_domain_contract
    validator = OUTCOME_VALIDATORS[policy&.domain]
    return unless validator

    validator.errors_for(outcome).each { |message| errors.add(:outcome, message) }
  end

  def conditions_are_well_formed
    unless conditions.is_a?(Array)
      errors.add(:conditions, "must be a list of conditions")
      return
    end

    conditions.each_with_index do |condition, index|
      unless condition.is_a?(Hash)
        errors.add(:conditions, "Condition #{index + 1} is not readable")
        next
      end

      condition = condition.with_indifferent_access
      errors.add(:conditions, "Condition #{index + 1} needs a field") if condition[:field].blank?

      operator = condition[:operator]
      unless OPERATORS.include?(operator)
        errors.add(:conditions, "Condition #{index + 1} has an unknown operator")
        next
      end

      validate_condition_value(condition, operator, index)
    end
  end

  def validate_condition_value(condition, operator, index)
    value = condition[:value]

    if ARRAY_VALUE_OPERATORS.include?(operator) && !(value.is_a?(Array) && value.any?)
      errors.add(:conditions, "Condition #{index + 1} needs at least one value")
    end

    if STRING_VALUE_OPERATORS.include?(operator) && !(value.is_a?(String) && value.present?)
      errors.add(:conditions, "Condition #{index + 1} needs a value")
    end

    if operator == OPERATOR_MATCHES_REGEX && value.is_a?(String)
      begin
        Regexp.new(value)
      rescue RegexpError => e
        errors.add(:conditions, "Condition #{index + 1} has a pattern Firefight cannot read: #{e.message}")
      end
    end
  end
end

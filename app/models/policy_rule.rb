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

  # Outcome contracts per policy domain; domains without a contract accept any object.
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
      errors.add(:conditions, "must be an array")
      return
    end

    conditions.each_with_index do |condition, index|
      unless condition.is_a?(Hash)
        errors.add(:conditions, "condition #{index} must be an object")
        next
      end

      condition = condition.with_indifferent_access
      errors.add(:conditions, "condition #{index} is missing a field") if condition[:field].blank?

      operator = condition[:operator]
      unless OPERATORS.include?(operator)
        errors.add(:conditions, "condition #{index} has unknown operator #{operator.inspect}")
        next
      end

      validate_condition_value(condition, operator, index)
    end
  end

  def validate_condition_value(condition, operator, index)
    value = condition[:value]

    if ARRAY_VALUE_OPERATORS.include?(operator) && !(value.is_a?(Array) && value.any?)
      errors.add(:conditions, "condition #{index} (#{operator}) requires a non-empty array value")
    end

    if STRING_VALUE_OPERATORS.include?(operator) && !(value.is_a?(String) && value.present?)
      errors.add(:conditions, "condition #{index} (#{operator}) requires a string value")
    end

    if operator == OPERATOR_MATCHES_REGEX && value.is_a?(String)
      begin
        Regexp.new(value)
      rescue RegexpError => e
        errors.add(:conditions, "condition #{index} has an invalid regex: #{e.message}")
      end
    end
  end
end

class IncidentConditionEvaluator
  def self.match?(conditions, context)
    return true if conditions.empty?

    conditions.all? { |condition| evaluate(condition, context) }
  end

  def self.evaluate(condition, context)
    actual_value = context[condition.condition_field.to_sym]
    target_values = condition.values

    case condition.operator
    when IncidentCondition::OPERATOR_ONE_OF
      target_values.include?(actual_value)
    when IncidentCondition::OPERATOR_NOT_ONE_OF
      !target_values.include?(actual_value)
    else
      true
    end
  end
end

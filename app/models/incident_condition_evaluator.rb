class IncidentConditionEvaluator
  def self.context_for(incident)
    {
      incident_type: incident.incident_type_id,
      severity: incident.incident_severity_id,
      custom_fields: incident.custom_fields.dup
    }.compact
  end

  def self.match?(conditions, context)
    return true if conditions.empty?

    conditions.all? { |condition| evaluate(condition, context) }
  end

  def self.evaluate(condition, context)
    if condition.condition_field == IncidentCondition::FIELD_CUSTOM_FIELD
      actual_value = context.dig(:custom_fields, condition.incident_field_definition.key)
    else
      actual_value = context[condition.condition_field.to_sym]
    end

    target_values = condition.values

    if actual_value.is_a?(Array)
      evaluate_array(condition.operator, actual_value, target_values)
    else
      evaluate_scalar(condition.operator, actual_value, target_values)
    end
  end

  def self.evaluate_array(operator, actual_values, target_values)
    intersects = (actual_values & target_values).any?

    case operator
    when IncidentCondition::OPERATOR_ONE_OF
      intersects
    when IncidentCondition::OPERATOR_NOT_ONE_OF
      !intersects
    else
      true
    end
  end

  def self.evaluate_scalar(operator, actual_value, target_values)
    case operator
    when IncidentCondition::OPERATOR_ONE_OF
      target_values.include?(actual_value)
    when IncidentCondition::OPERATOR_NOT_ONE_OF
      !target_values.include?(actual_value)
    else
      true
    end
  end
end

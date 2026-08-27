class IncidentConditionEvaluator
  # The one place the shape of a condition context is defined. Every caller
  # builds through here so a condition means the same thing wherever it is
  # evaluated.
  def self.context(incident_type: nil, severity: nil, status: nil, visibility: nil, custom_fields: nil)
    {
      incident_type: incident_type,
      severity: severity,
      status: status,
      visibility: visibility,
      custom_fields: custom_fields.presence&.dup
    }.compact
  end

  # What the incident will hold once the answers in front of the responder are
  # submitted, over whatever it already holds. Every surface asks through here,
  # because a form rendered against one context and validated against another
  # shows a field and then rejects it.
  #
  # `answers` is keyed the way a form is, system field key for the built-ins and
  # slug for a custom field. Declaring passes no incident, so it names the
  # workspace instead.
  def self.context_for(incident, workspace: nil, answers: {})
    answers = (answers || {}).stringify_keys
    workspace ||= incident&.workspace

    context(
      incident_type: answered_id(workspace, answers, :incident_types, IncidentSystemField::KEY_INCIDENT_TYPE, incident&.incident_type_id),
      severity: answered_id(workspace, answers, :incident_severities, IncidentSystemField::KEY_SEVERITY, incident&.incident_severity_id),
      status: answered_id(workspace, answers, :incident_statuses, IncidentSystemField::KEY_STATUS, incident&.incident_status_id),
      visibility: answered_visibility(answers, incident),
      custom_fields: (incident&.custom_fields || {}).merge(answered_custom_fields(workspace, answers))
    )
  end

  # An answer names a record by slug. Absent one, whatever the incident holds.
  def self.answered_id(workspace, answers, association, key, stored_id)
    slug = answers[key]
    return stored_id if slug.blank?

    workspace.public_send(association).where(slug: slug).pick(:id) || stored_id
  end
  private_class_method :answered_id

  def self.answered_visibility(answers, incident)
    answered = answers[IncidentSystemField::KEY_VISIBILITY]
    return answered if answered.present?
    return nil if incident.nil?

    incident.is_private ? Incident::VISIBILITY_PRIVATE : Incident::VISIBILITY_PUBLIC
  end
  private_class_method :answered_visibility

  # Nothing answered means nothing to look up, which keeps the common
  # context_for(incident) call free of extra queries.
  def self.answered_custom_fields(workspace, answers)
    return {} if answers.empty?

    answers.slice(*workspace.incident_field_definitions.active.pluck(:slug)).compact
  end
  private_class_method :answered_custom_fields

  def self.match?(conditions, context)
    return true if conditions.empty?

    conditions.all? { |condition| evaluate(condition, context) }
  end

  def self.evaluate(condition, context)
    if condition.condition_field == IncidentCondition::FIELD_CUSTOM_FIELD
      actual_value = context.dig(:custom_fields, condition.incident_field_definition.slug)
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

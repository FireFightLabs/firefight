class IncidentCondition < ApplicationRecord
  FIELD_INCIDENT_TYPE = "incident_type"
  FIELD_SEVERITY = "severity"
  FIELD_STATUS = "status"
  FIELD_VISIBILITY = "visibility"
  FIELD_CUSTOM_FIELD = "custom_field"
  CONDITION_FIELDS = [
    FIELD_INCIDENT_TYPE, FIELD_SEVERITY, FIELD_STATUS, FIELD_VISIBILITY, FIELD_CUSTOM_FIELD
  ].freeze

  OPERATOR_ONE_OF = "one_of"
  OPERATOR_NOT_ONE_OF = "not_one_of"
  OPERATORS = [ OPERATOR_ONE_OF, OPERATOR_NOT_ONE_OF ].freeze

  SUPPORTED_CUSTOM_FIELD_TYPES = [
    IncidentFieldDefinition::TYPE_SINGLE_SELECT,
    IncidentFieldDefinition::TYPE_MULTI_SELECT,
    IncidentFieldDefinition::TYPE_CATALOG_REFERENCE,
    IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
  ].freeze

  belongs_to :workspace
  belongs_to :conditionable, polymorphic: true
  belongs_to :incident_field_definition, optional: true

  validates :condition_field, presence: true, inclusion: { in: CONDITION_FIELDS }
  validates :operator, presence: true, inclusion: { in: OPERATORS }
  validates :values, presence: true

  validate :values_is_array
  validate :incident_field_definition_matches_condition_field
  validate :incident_field_definition_type_supported
  validate :conditionable_may_be_hidden
  validate :custom_field_is_answerable_here

  FIELD_LABELS = {
    FIELD_INCIDENT_TYPE => "Incident type",
    FIELD_SEVERITY => "Severity",
    FIELD_STATUS => "Status",
    FIELD_VISIBILITY => "Visibility"
  }.freeze

  OPERATOR_LABELS = {
    OPERATOR_ONE_OF => "is one of",
    OPERATOR_NOT_ONE_OF => "is not one of"
  }.freeze

  VISIBILITY_LABELS = {
    Incident::VISIBILITY_PRIVATE => "Private",
    Incident::VISIBILITY_PUBLIC => "Public"
  }.freeze

  # The rule in words, with names in place of ids: "Severity is one of
  # Critical, Major". Same wording as the settings screen's conditions column.
  def to_sentence
    label = condition_field == FIELD_CUSTOM_FIELD ? incident_field_definition&.name || "Custom field" : FIELD_LABELS[condition_field]
    "#{label} #{OPERATOR_LABELS[operator]} #{value_names.join(", ")}"
  end

  private

  def value_names
    names = case condition_field
    when FIELD_INCIDENT_TYPE then workspace.incident_types.where(id: values).index_by(&:id).transform_values(&:name)
    when FIELD_SEVERITY then workspace.incident_severities.where(id: values).index_by(&:id).transform_values(&:name)
    when FIELD_STATUS then workspace.incident_statuses.where(id: values).index_by(&:id).transform_values(&:name)
    when FIELD_VISIBILITY then VISIBILITY_LABELS
    when FIELD_CUSTOM_FIELD then incident_field_definition&.selectable_values || {}
    end
    values.map { |value| names[value] || value }
  end

  # A condition is a second way to hide a field, so it has to respect the same
  # lock the Visible toggle does. Severity and Status are NOT NULL on incidents,
  # and a condition that fails to match drops them from the resolved set, which
  # `validate_submission` reads too. The result was a Declare dialog that asked
  # for no severity and then refused every submission.
  def conditionable_may_be_hidden
    return unless conditionable.is_a?(IncidentFormField) && conditionable.locked_visible?

    errors.add(:base, "#{conditionable.source_name} is always asked for, so it cannot be made conditional.")
  end

  # A condition can only read a custom field the incident could already hold an
  # answer for. One attached to this form, or to a form that runs before it.
  # Pointing at a field nobody is ever asked produces a rule that silently never
  # matches, which reads as the field being broken.
  def custom_field_is_answerable_here
    return unless condition_field == FIELD_CUSTOM_FIELD && incident_field_definition.present?
    return unless conditionable.is_a?(IncidentFormField)

    form = conditionable.incident_form
    return if form.blank?
    return if form.condition_source_definitions.any? { |definition| definition.id == incident_field_definition_id }

    errors.add(:incident_field_definition,
               "is not asked for on the #{form.name} form or any form before it")
  end

  def values_is_array
    unless values.is_a?(Array)
      errors.add(:values, "must be an array")
    end
  end

  def incident_field_definition_matches_condition_field
    if condition_field == FIELD_CUSTOM_FIELD
      errors.add(:incident_field_definition, "can't be blank") if incident_field_definition.blank?
    elsif incident_field_definition.present?
      errors.add(:incident_field_definition, "must be blank unless condition is on a custom field")
    end
  end

  def incident_field_definition_type_supported
    return if incident_field_definition.blank?

    unless SUPPORTED_CUSTOM_FIELD_TYPES.include?(incident_field_definition.field_type)
      errors.add(:incident_field_definition, "field type is not supported for conditions")
    end
  end
end

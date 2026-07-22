class IncidentCondition < ApplicationRecord
  FIELD_INCIDENT_TYPE = "incident_type"
  FIELD_SEVERITY = "severity"
  FIELD_CUSTOM_FIELD = "custom_field"
  CONDITION_FIELDS = [ FIELD_INCIDENT_TYPE, FIELD_SEVERITY, FIELD_CUSTOM_FIELD ].freeze

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

  private

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

class IncidentCondition < ApplicationRecord
  FIELD_INCIDENT_TYPE = "incident_type"
  FIELD_SEVERITY = "severity"
  CONDITION_FIELDS = [ FIELD_INCIDENT_TYPE, FIELD_SEVERITY ].freeze

  OPERATOR_ONE_OF = "one_of"
  OPERATOR_NOT_ONE_OF = "not_one_of"
  OPERATORS = [ OPERATOR_ONE_OF, OPERATOR_NOT_ONE_OF ].freeze

  belongs_to :workspace
  belongs_to :conditionable, polymorphic: true

  validates :condition_field, presence: true, inclusion: { in: CONDITION_FIELDS }
  validates :operator, presence: true, inclusion: { in: OPERATORS }
  validates :values, presence: true

  validate :values_is_array

  private

  def values_is_array
    unless values.is_a?(Array)
      errors.add(:values, "must be an array")
    end
  end
end

require "test_helper"

class IncidentConditionTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_forms, :incident_form_fields, :incident_field_definitions

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @form_field = incident_form_fields(:declare_name_field_ws1)
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "valid condition" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "some-type-id" ]
    )
    assert condition.valid?
  end

  test "requires condition_field" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "id" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:condition_field], "can't be blank"
  end

  test "condition_field must be in allowed list" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: "invalid_field",
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "id" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:condition_field], "is not included in the list"
  end

  test "requires operator" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      values: [ "id" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:operator], "can't be blank"
  end

  test "operator must be in allowed list" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: "equals",
      values: [ "id" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:operator], "is not included in the list"
  end

  test "requires values" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: IncidentCondition::OPERATOR_ONE_OF
    )
    assert_not condition.valid?
  end

  test "values must be an array" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: "not-an-array"
    )
    assert_not condition.valid?
    assert_includes condition.errors[:values], "must be an array"
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "condition fields include incident_type and severity" do
    assert_includes IncidentCondition::CONDITION_FIELDS, IncidentCondition::FIELD_INCIDENT_TYPE
    assert_includes IncidentCondition::CONDITION_FIELDS, IncidentCondition::FIELD_SEVERITY
  end

  test "operators include one_of and not_one_of" do
    assert_includes IncidentCondition::OPERATORS, IncidentCondition::OPERATOR_ONE_OF
    assert_includes IncidentCondition::OPERATORS, IncidentCondition::OPERATOR_NOT_ONE_OF
  end
end

require "test_helper"

class IncidentConditionTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_forms, :incident_form_fields, :catalog_types, :incident_field_definitions, :incident_field_options

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
  # CUSTOM FIELD VALIDATIONS
  # ============================================================================

  test "valid custom_field condition with a supported field definition" do
    definition = incident_field_definitions(:customer_tier_ws1)
    IncidentFormService.new(@workspace).add_custom_field(@form_field.incident_form, definition)

    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      incident_field_definition: definition,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "Enterprise" ]
    )
    assert condition.valid?
  end

  # A rule pointing at a field nobody is ever asked never matches, which reads
  # as the field being broken rather than the rule being wrong.
  test "a custom field on no form cannot drive a condition" do
    definition = @workspace.incident_field_definitions.create!(
      name: "Blast radius", slug: "blast_radius", position: 90,
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG,
      catalog_type: catalog_types(:service_ws1)
    )

    condition = IncidentCondition.new(
      workspace: @workspace, conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      incident_field_definition: definition,
      operator: IncidentCondition::OPERATOR_ONE_OF, values: [ "x" ]
    )

    assert_not condition.valid?
    assert_match(/is not asked for on the/, condition.errors.full_messages.to_sentence)
  end

  # Declare runs before Resolve, so a Resolve condition may read what was
  # answered at declare time. The reverse is not true.
  test "a later form can read an earlier form's custom field" do
    definition = incident_field_definitions(:customer_tier_ws1)
    declare = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    resolve = @workspace.ensure_incident_form!(IncidentForm::SLUG_RESOLVE)
    IncidentFormService.new(@workspace).add_custom_field(declare, definition)
    target = IncidentFormService.new(@workspace).ensure_system_field!(resolve, IncidentSystemField::KEY_NAME)

    condition = IncidentCondition.new(
      workspace: @workspace, conditionable: target,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      incident_field_definition: definition,
      operator: IncidentCondition::OPERATOR_ONE_OF, values: [ "Enterprise" ]
    )

    assert condition.valid?, condition.errors.full_messages.to_sentence
  end

  test "custom_field condition requires an incident_field_definition" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "Enterprise" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:incident_field_definition], "can't be blank"
  end

  test "non custom_field condition must not have an incident_field_definition" do
    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      incident_field_definition: incident_field_definitions(:customer_tier_ws1),
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "id" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:incident_field_definition], "must be blank unless condition is on a custom field"
  end

  test "custom_field condition rejects unsupported field definition types" do
    text_definition = @workspace.incident_field_definitions.create!(
      slug: "root_cause_notes",
      name: "Root Cause Notes",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE,
      position: 99
    )

    condition = IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      incident_field_definition: text_definition,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ "anything" ]
    )
    assert_not condition.valid?
    assert_includes condition.errors[:incident_field_definition], "field type is not supported for conditions"
  end

  test "supported custom field types constant" do
    assert_includes IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES, IncidentFieldDefinition::TYPE_SINGLE_SELECT
    assert_includes IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES, IncidentFieldDefinition::TYPE_MULTI_SELECT
    assert_includes IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES, IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
    assert_includes IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES, IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
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

  # A condition is a second way to hide a field, and it used to bypass the lock
  # the Visible toggle respects. Severity dropped out of the Declare form, took
  # itself out of validate_submission with it, and every declaration then failed
  # on a nil severity. The editor already refused this; the MCP tool did not.
  test "a locked field cannot be made conditional" do
    workspace = workspaces(:slack_workspace_one)
    form = workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    severity = IncidentFormService.new(workspace).ensure_system_field!(form, IncidentSystemField::KEY_SEVERITY)
    assert severity.locked_visible?, "expected severity to be locked"

    condition = IncidentCondition.new(
      workspace: workspace, conditionable: severity,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ workspace.incident_types.active.first.id ]
    )

    assert_not condition.valid?
    assert_match(/cannot be made conditional/, condition.errors.full_messages.to_sentence)
  end

  test "a locked field stays in the form even if a condition predates the rule" do
    workspace = workspaces(:slack_workspace_one)
    form = workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    severity = IncidentFormService.new(workspace).ensure_system_field!(form, IncidentSystemField::KEY_SEVERITY)

    IncidentCondition.new(
      workspace: workspace, conditionable: severity,
      condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ workspace.incident_types.active.first.id ]
    ).save!(validate: false)

    resolved = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_DECLARE, context: {})
    assert_includes resolved.map(&:system_field_key), IncidentSystemField::KEY_SEVERITY
  end
end

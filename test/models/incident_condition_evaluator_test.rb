require "test_helper"

class IncidentConditionEvaluatorTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_forms, :incident_form_fields, :incident_field_definitions

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @form_field = incident_form_fields(:declare_name_field_ws1)
  end

  # ============================================================================
  # MATCH? WITH EMPTY CONDITIONS
  # ============================================================================

  test "match? returns true when conditions are empty" do
    assert IncidentConditionEvaluator.match?([], { incident_type: "any" })
  end

  # ============================================================================
  # ONE_OF OPERATOR
  # ============================================================================

  test "one_of matches when value is in target list" do
    condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "type-a", "type-b" ]
    )

    assert IncidentConditionEvaluator.match?([ condition ], { incident_type: "type-a" })
  end

  test "one_of does not match when value is not in target list" do
    condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "type-a", "type-b" ]
    )

    assert_not IncidentConditionEvaluator.match?([ condition ], { incident_type: "type-c" })
  end

  test "one_of does not match when context value is nil" do
    condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "type-a" ]
    )

    assert_not IncidentConditionEvaluator.match?([ condition ], { incident_type: nil })
  end

  # ============================================================================
  # NOT_ONE_OF OPERATOR
  # ============================================================================

  test "not_one_of matches when value is not in target list" do
    condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_NOT_ONE_OF,
      [ "type-a" ]
    )

    assert IncidentConditionEvaluator.match?([ condition ], { incident_type: "type-b" })
  end

  test "not_one_of does not match when value is in target list" do
    condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_NOT_ONE_OF,
      [ "type-a", "type-b" ]
    )

    assert_not IncidentConditionEvaluator.match?([ condition ], { incident_type: "type-a" })
  end

  # ============================================================================
  # MULTIPLE CONDITIONS (AND LOGIC)
  # ============================================================================

  test "multiple conditions use AND logic — all must match" do
    type_condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "production" ]
    )
    severity_condition = build_condition(
      IncidentCondition::FIELD_SEVERITY,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "critical" ]
    )

    assert IncidentConditionEvaluator.match?(
      [ type_condition, severity_condition ],
      { incident_type: "production", severity: "critical" }
    )
  end

  test "multiple conditions fail if one does not match" do
    type_condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "production" ]
    )
    severity_condition = build_condition(
      IncidentCondition::FIELD_SEVERITY,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "critical" ]
    )

    assert_not IncidentConditionEvaluator.match?(
      [ type_condition, severity_condition ],
      { incident_type: "production", severity: "minor" }
    )
  end

  # ============================================================================
  # SEVERITY CONDITION
  # ============================================================================

  test "severity condition matches correctly" do
    condition = build_condition(
      IncidentCondition::FIELD_SEVERITY,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "critical", "major" ]
    )

    assert IncidentConditionEvaluator.match?([ condition ], { severity: "critical" })
    assert IncidentConditionEvaluator.match?([ condition ], { severity: "major" })
    assert_not IncidentConditionEvaluator.match?([ condition ], { severity: "minor" })
  end

  # ============================================================================
  # CUSTOM FIELD CONDITIONS
  # ============================================================================

  test "custom_field one_of matches scalar value present in target list" do
    defn = incident_field_definitions(:customer_tier_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_ONE_OF, [ "Enterprise", "Pro" ])

    assert IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "customer_tier" => "Enterprise" } })
    assert_not IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "customer_tier" => "Free" } })
  end

  test "custom_field not_one_of matches scalar value absent from target list" do
    defn = incident_field_definitions(:customer_tier_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_NOT_ONE_OF, [ "Enterprise" ])

    assert IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "customer_tier" => "Free" } })
    assert_not IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "customer_tier" => "Enterprise" } })
  end

  test "custom_field one_of matches array actual when intersection is non-empty" do
    defn = incident_field_definitions(:affected_services_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_ONE_OF, [ "svc-a", "svc-b" ])

    assert IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "affected_services" => [ "svc-b", "svc-c" ] } })
    assert_not IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "affected_services" => [ "svc-x" ] } })
  end

  test "custom_field not_one_of matches array actual when intersection is empty" do
    defn = incident_field_definitions(:affected_services_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_NOT_ONE_OF, [ "svc-a" ])

    assert IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "affected_services" => [ "svc-b" ] } })
    assert_not IncidentConditionEvaluator.match?([ condition ], { custom_fields: { "affected_services" => [ "svc-a", "svc-b" ] } })
  end

  test "custom_field one_of does not match when actual value is missing" do
    defn = incident_field_definitions(:customer_tier_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_ONE_OF, [ "Enterprise" ])

    assert_not IncidentConditionEvaluator.match?([ condition ], { custom_fields: {} })
    assert_not IncidentConditionEvaluator.match?([ condition ], {})
  end

  test "custom_field not_one_of matches when actual value is missing" do
    defn = incident_field_definitions(:customer_tier_ws1)
    condition = build_custom_field_condition(defn, IncidentCondition::OPERATOR_NOT_ONE_OF, [ "Enterprise" ])

    assert IncidentConditionEvaluator.match?([ condition ], { custom_fields: {} })
    assert IncidentConditionEvaluator.match?([ condition ], {})
  end

  test "backward compatible with contexts that omit custom_fields" do
    type_condition = build_condition(
      IncidentCondition::FIELD_INCIDENT_TYPE,
      IncidentCondition::OPERATOR_ONE_OF,
      [ "production" ]
    )

    assert IncidentConditionEvaluator.match?([ type_condition ], { incident_type: "production" })
    assert_not IncidentConditionEvaluator.match?([ type_condition ], { incident_type: "staging" })
  end

  private

  def build_condition(field, operator, values)
    IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: field,
      operator: operator,
      values: values
    )
  end

  def build_custom_field_condition(definition, operator, values)
    IncidentCondition.new(
      workspace: @workspace,
      conditionable: @form_field,
      condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
      incident_field_definition: definition,
      operator: operator,
      values: values
    )
  end
end

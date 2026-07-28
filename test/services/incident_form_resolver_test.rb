require "test_helper"

class IncidentFormResolverTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_forms, :incident_form_fields, :incident_field_definitions,
           :catalog_types, :catalog_entries

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @resolver = IncidentFormResolver.new(@workspace)
  end

  # ============================================================================
  # RESOLVE
  # ============================================================================

  test "resolve returns visible fields for a lifecycle event" do
    fields = @resolver.resolve(IncidentForm::SLUG_DECLARE)

    assert fields.any?
    assert fields.all? { |f| f.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE }
  end

  test "resolve orders fields by position" do
    fields = @resolver.resolve(IncidentForm::SLUG_DECLARE)

    positions = fields.map(&:position)
    assert_equal positions.sort, positions
  end

  test "resolve drops custom fields whose definition is disabled" do
    field = @resolver.resolve(IncidentForm::SLUG_DECLARE).find(&:custom?)
    assert field, "expected a custom field on the declare form"

    definition = field.incident_field_definition
    definition.update!(deleted_at: Time.current)

    ids = @resolver.resolve(IncidentForm::SLUG_DECLARE).map(&:id)
    assert_not_includes ids, field.id

    definition.update!(deleted_at: nil)
    assert_includes @resolver.resolve(IncidentForm::SLUG_DECLARE).map(&:id), field.id
  end

  test "resolve raises for unknown lifecycle event" do
    assert_raises(ArgumentError) do
      @resolver.resolve("nonexistent")
    end
  end

  # ============================================================================
  # VALIDATE_SUBMISSION — SYSTEM FIELDS
  # ============================================================================

  test "valid submission with system fields returns no errors" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "name" => "Server outage",
      "severity" => "critical"
    })

    assert_empty result[:errors]
    assert_equal "Server outage", result[:system_attrs]["name"]
    assert_equal "critical", result[:system_attrs]["severity"]
    assert_empty result[:custom_fields]
  end

  test "missing required system field returns error" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "name" => "Server outage"
    })

    assert result[:errors].any? { |e| e.include?("Severity") && e.include?("required") }
  end

  test "missing optional system field is allowed" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical"
    })

    refute result[:errors].any? { |e| e.include?("Name") }
  end

  test "blank required system field returns error" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => ""
    })

    assert result[:errors].any? { |e| e.include?("Severity") && e.include?("required") }
  end

  # ============================================================================
  # VALIDATE_SUBMISSION — CUSTOM FIELDS
  # ============================================================================

  test "valid catalog_multi_reference value accepted" do
    entry = catalog_entries(:auth_service)

    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical",
      "affected_services" => [ entry.id ]
    })

    assert_empty result[:errors]
    assert_equal [ entry.id ], result[:custom_fields]["affected_services"]
  end

  test "invalid catalog reference returns error" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical",
      "affected_services" => [ "nonexistent-uuid" ]
    })

    assert result[:errors].any? { |e| e.include?("Affected Services") && e.include?("invalid catalog entry") }
  end

  test "catalog_multi_reference must be an array" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical",
      "affected_services" => "not-an-array"
    })

    assert result[:errors].any? { |e| e.include?("Affected Services") && e.include?("array") }
  end

  # ============================================================================
  # VALIDATE_SUBMISSION — UNKNOWN FIELDS
  # ============================================================================

  test "unknown fields are rejected" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical",
      "unknown_field" => "bad value"
    })

    assert result[:errors].any? { |e| e.include?("Unknown fields") && e.include?("unknown_field") }
  end

  # ============================================================================
  # VALIDATE_SUBMISSION — SYMBOL KEYS
  # ============================================================================

  test "symbol keys are normalized to strings" do
    result = @resolver.validate_submission(IncidentForm::SLUG_DECLARE, {
      severity: "critical",
      name: "Test"
    })

    assert_empty result[:errors]
    assert_equal "critical", result[:system_attrs]["severity"]
    assert_equal "Test", result[:system_attrs]["name"]
  end

  # ============================================================================
  # VALIDATE_SUBMISSION!
  # ============================================================================

  test "validate_submission! raises on errors" do
    assert_raises(IncidentFormResolver::ValidationError) do
      @resolver.validate_submission!(IncidentForm::SLUG_DECLARE, {})
    end
  end

  test "validate_submission! returns result on success" do
    result = @resolver.validate_submission!(IncidentForm::SLUG_DECLARE, {
      "severity" => "critical"
    })

    assert_equal "critical", result[:system_attrs]["severity"]
  end

  # ============================================================================
  # RESOLVE FORM
  # ============================================================================

  test "resolve form returns different fields for different lifecycle events" do
    declare_fields = @resolver.resolve(IncidentForm::SLUG_DECLARE)
    resolve_fields = @resolver.resolve(IncidentForm::SLUG_RESOLVE)

    declare_keys = declare_fields.map { |f| f.system_field_key || f.incident_field_definition&.key }
    resolve_keys = resolve_fields.map { |f| f.system_field_key || f.incident_field_definition&.key }

    assert_not_equal declare_keys, resolve_keys
  end
end

require "test_helper"

class IncidentFormResolverTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_forms, :incident_form_fields, :incident_field_definitions,
           :catalog_types, :catalog_entries, :incident_lifecycle_stages, :incident_statuses,
           :incident_types

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

    declare_keys = declare_fields.map { |f| f.system_field_key || f.incident_field_definition&.slug }
    resolve_keys = resolve_fields.map { |f| f.system_field_key || f.incident_field_definition&.slug }

    assert_not_equal declare_keys, resolve_keys
  end

  # ============================================================================
  # UNANSWERABLE FIELDS
  #
  # Every one of these used to be suppressed in the Slack block builder alone,
  # which left validate_submission demanding a field the modal never rendered.
  # ============================================================================

  test "a status an override row materialized is still dropped while the stage holds one status" do
    fixtures_workspace_has_one_canceled_status

    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    IncidentFormService.new(@workspace).ensure_system_field!(form, IncidentSystemField::KEY_STATUS)

    keys = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_CANCEL).map(&:system_field_key)
    assert_not_includes keys, IncidentSystemField::KEY_STATUS
  end

  test "a materialized status does not become required on submission after the modal skipped it" do
    fixtures_workspace_has_one_canceled_status

    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    row = IncidentFormService.new(@workspace).ensure_system_field!(form, IncidentSystemField::KEY_STATUS)
    row.update!(required_mode: IncidentFormField::REQUIRED_MODE_REQUIRED)

    result = IncidentFormResolver.new(@workspace).validate_submission(IncidentForm::SLUG_CANCEL, {})
    assert_empty result[:errors]
  end

  test "an override row carries the reason it will not reach responders" do
    fixtures_workspace_has_one_canceled_status

    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    IncidentFormService.new(@workspace).ensure_system_field!(form, IncidentSystemField::KEY_STATUS)

    field = IncidentFormResolver.new(@workspace)
      .resolve(IncidentForm::SLUG_CANCEL, include_hidden: true)
      .find { |f| f.system_field_key == IncidentSystemField::KEY_STATUS }

    assert_match(/only one canceled status/, field.inactive_reason)
  end

  test "incident type is dropped while the workspace has none" do
    @workspace.incident_types.update_all(deleted_at: Time.current)

    keys = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_DECLARE).map(&:system_field_key)
    assert_not_includes keys, IncidentSystemField::KEY_INCIDENT_TYPE
  end

  test "a catalog field whose type holds no entries is dropped rather than asked" do
    empty_type = @workspace.catalog_types.create!(
      name: "Blast radius", slug: "blast_radius", kind: CatalogType::KIND_CUSTOM, position: 90
    )
    definition = @workspace.incident_field_definitions.create!(
      name: "Blast radius", slug: "blast_radius", position: 90,
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG,
      catalog_type: empty_type
    )
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    IncidentFormService.new(@workspace).add_custom_field(form, definition)

    resolver = IncidentFormResolver.new(@workspace)
    slugs = resolver.resolve(IncidentForm::SLUG_DECLARE).filter_map { |f| f.incident_field_definition&.slug }
    assert_not_includes slugs, "blast_radius"

    field = IncidentFormResolver.new(@workspace)
      .resolve(IncidentForm::SLUG_DECLARE, include_hidden: true)
      .find { |f| f.incident_field_definition&.slug == "blast_radius" }
    assert_match(/at least one option/, field.inactive_reason)
  end

  # ============================================================================
  # CONDITIONS
  # ============================================================================

  # The Declare modal opens before anything has been chosen, so the context is
  # empty. Treating that as "no filtering" showed every conditional field on
  # first render and then hid it once a type was picked.
  test "a conditional field is hidden until its condition is met" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    definition = @workspace.incident_field_definitions.create!(
      name: "Affected region", slug: "affected_region", position: 80,
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE
    )
    field = IncidentFormService.new(@workspace).add_custom_field(form, definition)
    production = @workspace.incident_types.active.first
    field.sync_conditions!([ { condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
                               operator: IncidentCondition::OPERATOR_ONE_OF,
                               values: [ production.id ] } ])

    resolver = IncidentFormResolver.new(@workspace)

    nothing_chosen = resolver.resolve(IncidentForm::SLUG_DECLARE, context: {})
    assert_not_includes slugs(nothing_chosen), "affected_region"

    other_type = @workspace.incident_types.active.where.not(id: production.id).first
    wrong_type = resolver.resolve(IncidentForm::SLUG_DECLARE,
                                  context: IncidentConditionEvaluator.context(incident_type: other_type.id))
    assert_not_includes slugs(wrong_type), "affected_region"

    matching = resolver.resolve(IncidentForm::SLUG_DECLARE,
                                context: IncidentConditionEvaluator.context(incident_type: production.id))
    assert_includes slugs(matching), "affected_region"
  end

  test "the editor still lists a conditional field so its condition can be changed" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    definition = @workspace.incident_field_definitions.create!(
      name: "Affected region", slug: "affected_region", position: 81,
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE
    )
    field = IncidentFormService.new(@workspace).add_custom_field(form, definition)
    field.sync_conditions!([ { condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
                               operator: IncidentCondition::OPERATOR_ONE_OF,
                               values: [ @workspace.incident_types.active.first.id ] } ])

    editor = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_DECLARE, include_hidden: true)
    assert_includes slugs(editor), "affected_region"
  end

  # The channel is named from the incident name once, at creation, and cannot
  # be renamed later. The API already requires it and alerts derive it from the
  # alert title, so Slack was the only path that let a blank through.
  # Asserted on the registry, since this workspace's fixtures carry an override
  # row for name and an override is meant to win.
  test "name ships required on declare" do
    definition = IncidentSystemField.fetch(IncidentSystemField::KEY_NAME)

    assert_equal IncidentFormField::REQUIRED_MODE_REQUIRED,
                 definition.required_mode_for(IncidentForm::SLUG_DECLARE)
  end

  # What a brand new workspace is asked, before anyone configures anything.
  # Everything else stays listed in the editor, switched off.
  test "the shipped forms ask for a deliberate set" do
    expected = {
      IncidentForm::SLUG_DECLARE => [ "Name", "Severity", "Summary" ],
      IncidentForm::SLUG_UPDATE => [ "Message", "Next Update", "Status", "Severity" ],
      IncidentForm::SLUG_RESOLVE => [ "Name", "Status", "Severity", "Summary", "Incident Lead" ],
      IncidentForm::SLUG_CANCEL => [ "Status" ]
    }

    expected.each do |slug, names|
      on = IncidentSystemField.defaults_for(slug).reject do |definition|
        definition.required_mode_for(slug) == IncidentFormField::REQUIRED_MODE_AVAILABLE
      end
      assert_equal names, on.map(&:name), "default fields on the #{slug} form"
    end
  end

  test "a field that is off by default is still offered in the editor" do
    workspace = workspaces(:slack_workspace_two)
    editor = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_DECLARE, include_hidden: true)
    responders = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_DECLARE)

    assert_includes editor.map(&:system_field_key), IncidentSystemField::KEY_INCIDENT_TYPE
    assert_not_includes responders.map(&:system_field_key), IncidentSystemField::KEY_INCIDENT_TYPE
  end

  test "a workspace with no override gets the required default" do
    @workspace.incident_forms.find_by(lifecycle_event: IncidentForm::SLUG_DECLARE)
      &.incident_form_fields&.where(system_field_key: IncidentSystemField::KEY_NAME)&.destroy_all

    field = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_DECLARE)
      .find { |f| f.system_field_key == IncidentSystemField::KEY_NAME }

    assert_equal IncidentFormField::REQUIRED_MODE_REQUIRED, field.required_mode
  end

  test "a workspace can still make name optional again" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    row = IncidentFormService.new(@workspace).ensure_system_field!(form, IncidentSystemField::KEY_NAME)
    IncidentFormService.new(@workspace).update_field(
      row,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    result = IncidentFormResolver.new(@workspace).validate_submission(
      IncidentForm::SLUG_DECLARE, { "severity" => "critical" }
    )
    assert_empty result[:errors]
  end

  private

  def slugs(fields)
    fields.filter_map { |field| field.system_field_key || field.incident_field_definition&.slug }
  end

  def fixtures_workspace_has_one_canceled_status
    stage = IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::CANCELED)
    assert_equal 1, @workspace.incident_statuses.active.where(incident_lifecycle_stage: stage).count
  end
end

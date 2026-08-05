require "test_helper"

class McpFormToolsTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_types, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @token = create_service_key(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
  end

  def call_tool(name, arguments = {})
    post mcp_path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: name, arguments: arguments } }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    result = JSON.parse(response.body).fetch("result")
    [ result["structuredContent"] || {}, result["isError"] ]
  end

  test "upsert_custom_field creates a fixed list field with its options in order" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_CUSTOM_FIELD, {
      name: "Impacted regions",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ "Payments", "Checkout" ]
    })

    assert_not is_error
    assert_equal "impacted_regions", content["slug"]
    assert_equal [ "Payments", "Checkout" ], content["options"].map { |o| o["label"] }
  end

  test "renaming through options keeps the option id incidents point at" do
    call_tool(Mcp::Tools::UPSERT_CUSTOM_FIELD, {
      name: "Impacted regions",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ "Payments", "Checkout" ]
    })
    definition = @workspace.incident_field_definitions.find_by!(slug: "impacted_regions")
    payments_id = definition.incident_field_options.find_by!(label: "Payments").id

    content, _ = call_tool(Mcp::Tools::UPSERT_CUSTOM_FIELD, {
      slug: "impacted_regions",
      options: [ "Payments", "Checkout", "Search" ]
    })

    kept = content["options"].find { |o| o["label"] == "Payments" }
    assert_equal payments_id, kept["id"]
    assert_equal [ "Payments", "Checkout", "Search" ], content["options"].map { |o| o["label"] }
  end

  test "upsert_form_field attaches a custom field and gates it on an incident type slug" do
    call_tool(Mcp::Tools::UPSERT_CUSTOM_FIELD, {
      name: "Impacted regions",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ "Payments" ]
    })

    content, is_error = call_tool(Mcp::Tools::UPSERT_FORM_FIELD, {
      form: IncidentForm::SLUG_DECLARE,
      custom_field: "impacted_regions",
      required: true,
      conditions: [ { condition_field: "incident_type", operator: "one_of", values: [ "service_outage" ] } ]
    })

    assert_not is_error
    assert content["required"]
    assert_equal 1, content["conditions"]

    production = @workspace.incident_types.find_by!(slug: "service_outage")
    field = @workspace.incident_forms.find_by!(slug: IncidentForm::SLUG_DECLARE)
      .incident_form_fields.joins(:incident_field_definition)
      .find_by!(incident_field_definitions: { slug: "impacted_regions" })
    assert_equal [ production.id ], field.incident_conditions.first.values
  end

  test "upsert_form_field refuses to hide a field the incident cannot be written without" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_FORM_FIELD, {
      form: IncidentForm::SLUG_DECLARE,
      system_field: IncidentSystemField::KEY_SEVERITY,
      visible: false
    })

    assert_not is_error
    assert content["visible"], "severity must stay visible"
    assert content["locked"]
  end

  test "get_form lists hidden fields so an agent can see what it would replace" do
    call_tool(Mcp::Tools::UPSERT_FORM_FIELD, {
      form: IncidentForm::SLUG_DECLARE,
      system_field: IncidentSystemField::KEY_NAME,
      visible: false
    })

    content, is_error = call_tool(Mcp::Tools::GET_FORM, { form: IncidentForm::SLUG_DECLARE })

    assert_not is_error
    name_field = content["fields"].find { |f| f["slug"] == IncidentSystemField::KEY_NAME }
    assert name_field
    assert_not name_field["visible"]
  end

  test "an unknown form is refused with the valid slugs named" do
    content, is_error = call_tool(Mcp::Tools::GET_FORM, { form: "postmortem" })

    assert is_error
    assert_empty content
  end

  # The tests above run on a personal token, which carries its human's
  # authority and so never touches a grant. A service key is the path where
  # scopes actually decide, and it is the one the permissions screen has to be
  # able to issue.

  test "a service key scoped to forms can read and configure them" do
    @token = service_token(ApiKey::RESOURCE_FORMS => [ ApiKey::ACTION_READ, ApiKey::ACTION_UPDATE ])

    _, read_error = call_tool(Mcp::Tools::GET_FORM, { form: IncidentForm::SLUG_DECLARE })
    assert_not read_error

    _, write_error = call_tool(Mcp::Tools::UPSERT_FORM_FIELD, {
      form: IncidentForm::SLUG_DECLARE,
      system_field: IncidentSystemField::KEY_NAME,
      required: true
    })
    assert_not write_error
  end

  # Defining a custom field and deciding what every responder is asked are
  # separate powers, so one grant must not buy the other.
  test "a service key scoped to custom fields cannot configure a form" do
    @token = service_token(ApiKey::RESOURCE_CUSTOM_FIELDS => [ ApiKey::ACTION_READ, ApiKey::ACTION_UPDATE ])

    _, is_error = call_tool(Mcp::Tools::UPSERT_FORM_FIELD, {
      form: IncidentForm::SLUG_DECLARE,
      system_field: IncidentSystemField::KEY_NAME,
      required: true
    })

    assert is_error
  end

  private

  def service_token(permissions)
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Service", permissions: permissions
    )
    token
  end
end

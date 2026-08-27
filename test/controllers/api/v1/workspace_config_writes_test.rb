require "test_helper"

# The four configuration areas that were read-only or missing over REST. Each
# calls the same code the MCP tool calls, so a workspace set up through one is
# indistinguishable from one set up through the other.
class Api::V1::WorkspaceConfigWritesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Admin"
    )
  end

  test "a custom field is created with its options" do
    post api_v1_custom_fields_url,
         params: { name: "Affected region", field_type: "single_select", option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED, options: %w[eu-west us-east] },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    field = @workspace.incident_field_definitions.find_by!(slug: "affected_region")
    assert_equal %w[eu-west us-east], field.incident_field_options.active.map(&:label)
  end

  # Options are matched by label, so a resend renames rather than replaces and
  # the incidents already holding one keep pointing at it.
  test "resending an option list keeps the rows the incidents point at" do
    post api_v1_custom_fields_url,
         params: { name: "Affected region", field_type: "single_select", option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED, options: %w[eu-west us-east] },
         headers: api_headers(token: @admin_token), as: :json
    assert_response :created
    field = @workspace.incident_field_definitions.find_by!(slug: "affected_region")
    kept = field.incident_field_options.find_by!(label: "eu-west")

    patch api_v1_custom_field_url(field.slug),
          params: { options: %w[eu-west ap-south] }, headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_equal kept.id, field.reload.incident_field_options.find_by!(label: "eu-west").id
  end

  test "a runbook is created with its steps" do
    post api_v1_runbooks_url,
         params: { name: "Database failover", summary: "When the primary is gone.",
                   steps: [ { title: "Drain the primary" }, { title: "Promote the replica" } ] },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    runbook = @workspace.runbooks.find_by!(slug: "database_failover")
    assert_equal [ "Drain the primary", "Promote the replica" ], runbook.runbook_steps.order(:position).map(&:title)
  end

  # Steps are only touched when they are sent, so changing a summary must not
  # silently clear the procedure.
  test "changing a summary leaves the steps alone" do
    post api_v1_runbooks_url,
         params: { name: "Database failover", steps: [ { title: "Drain the primary" } ] },
         headers: api_headers(token: @admin_token), as: :json
    assert_response :created
    runbook = @workspace.runbooks.find_by!(slug: "database_failover")

    patch api_v1_runbook_url(runbook.slug),
          params: { summary: "Rewritten." }, headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_equal 1, runbook.reload.runbook_steps.count
  end

  test "a form says what it asks for, including the hidden fields" do
    get api_v1_form_url(IncidentForm::SLUG_DECLARE), headers: api_headers(token: @admin_token)

    assert_response :success
    assert_equal IncidentForm::SLUG_DECLARE, json_response["form"]
    assert json_response["fields"].any?
    assert json_response["fields"].all? { |f| f.key?("visible") && f.key?("required") }
  end

  test "an unknown form is refused rather than treated as empty" do
    get api_v1_form_url("not_a_form"), headers: api_headers(token: @admin_token)

    assert_response :bad_request
  end

  test "attaching a custom field to a form makes the form ask for it" do
    post api_v1_custom_fields_url,
         params: { name: "Affected region", field_type: "text", option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE },
         headers: api_headers(token: @admin_token), as: :json
    assert_response :created

    patch api_v1_form_url(IncidentForm::SLUG_DECLARE),
          params: { custom_field: "affected_region", visible: true, required: true },
          headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert json_response["visible"]
    assert json_response["required"]

    get api_v1_form_url(IncidentForm::SLUG_DECLARE), headers: api_headers(token: @admin_token)
    assert_includes json_response["fields"].map { |f| f["slug"] }, "affected_region"
  end

  test "a routing rule is created for the workspace and read back" do
    post api_v1_routing_rules_url,
         params: { conditions: [ { field: "severity", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "critical" ] } ],
                   outcome: { action: PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY } },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    assert_equal 1, json_response["priority"]

    get api_v1_routing_rules_url, headers: api_headers(token: @admin_token)
    assert_equal 1, json_response["routing_rules"].size
  end

  test "a dry run answers what an alert would do without creating anything" do
    post api_v1_routing_rules_url,
         params: { conditions: [], outcome: { action: PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY } },
         headers: api_headers(token: @admin_token), as: :json

    assert_no_difference -> { @workspace.incidents.count } do
      post api_v1_evaluate_routing_url,
           params: { fields: { severity: "critical" } }, headers: api_headers(token: @admin_token), as: :json
    end

    assert_response :success
    assert json_response.key?("matched")
    assert json_response.key?("trace")
  end

  test "a dry run with no policy says so rather than pretending nothing matched" do
    post api_v1_evaluate_routing_url,
         params: { fields: { severity: "critical" } }, headers: api_headers(token: @admin_token), as: :json

    assert_response :unprocessable_entity
    assert_match(/No enabled alert routing policy/, json_response.dig("error", "message"))
  end

  test "a key granted only incident reads cannot write configuration" do
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    post api_v1_custom_fields_url, params: { name: "Sneaky", field_type: "text", option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE },
         headers: api_headers(token: token), as: :json
    assert_response :forbidden

    post api_v1_runbooks_url, params: { name: "Sneaky" }, headers: api_headers(token: token), as: :json
    assert_response :forbidden

    patch api_v1_form_url(IncidentForm::SLUG_DECLARE), params: { system_field: "name", required: true },
          headers: api_headers(token: token), as: :json
    assert_response :forbidden
  end
end

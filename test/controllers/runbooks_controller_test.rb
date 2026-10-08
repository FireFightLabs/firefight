require "test_helper"

class RunbooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)

    @runbook = @workspace.runbooks.create!(name: "Existing")
    @runbook.runbook_steps.create!(title: "Old step", instruction: "Old", position: 1)
    @runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ incident_severities(:critical_ws1).id ]
    )
  end

  test "create with steps and conditions" do
    post runbooks_url(format: :html), params: {
      name: "Database Failover",
      summary: "How to fail over",
      content: "# Steps",
      external_url: "https://wiki.example.com/failover",
      steps: [
        { title: "Promote replica", instruction: "Run the failover script" },
        { title: "Verify writes", instruction: "Check the primary" }
      ],
      conditions: [
        {
          condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
          operator: IncidentCondition::OPERATOR_ONE_OF,
          values: [ incident_types(:service_outage_ws1).id ]
        }
      ]
    }
    assert_response :redirect

    runbook = Runbook.find_by!(slug: "database_failover", workspace: @workspace)
    assert_equal [ "Promote replica", "Verify writes" ], runbook.runbook_steps.ordered.map(&:title)
    assert_equal [ 1, 2 ], runbook.runbook_steps.ordered.map(&:position)

    condition = runbook.incident_conditions.sole
    assert_equal IncidentCondition::FIELD_INCIDENT_TYPE, condition.condition_field
    assert_equal [ incident_types(:service_outage_ws1).id ], condition.values
  end

  test "create with a custom field condition" do
    definition = incident_field_definitions(:customer_tier_ws1)

    post runbooks_url(format: :html), params: {
      name: "Enterprise escalation",
      conditions: [
        {
          condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
          operator: IncidentCondition::OPERATOR_ONE_OF,
          values: [ "Enterprise" ],
          incident_field_definition_id: definition.id
        }
      ]
    }
    assert_response :redirect

    runbook = Runbook.find_by!(slug: "enterprise_escalation", workspace: @workspace)
    condition = runbook.incident_conditions.sole
    assert_equal IncidentCondition::FIELD_CUSTOM_FIELD, condition.condition_field
    assert_equal definition.id, condition.incident_field_definition_id
    assert_equal [ "Enterprise" ], condition.values
  end

  test "update to a custom field condition" do
    definition = incident_field_definitions(:customer_tier_ws1)

    patch runbook_url(@runbook), params: {
      name: "Existing",
      conditions: [
        {
          condition_field: IncidentCondition::FIELD_CUSTOM_FIELD,
          operator: IncidentCondition::OPERATOR_ONE_OF,
          values: [ "Pro" ],
          incident_field_definition_id: definition.id
        }
      ]
    }
    assert_response :redirect

    condition = @runbook.reload.incident_conditions.sole
    assert_equal IncidentCondition::FIELD_CUSTOM_FIELD, condition.condition_field
    assert_equal definition.id, condition.incident_field_definition_id
  end

  test "update replaces steps and conditions" do
    patch runbook_url(@runbook), params: {
      name: "Existing",
      steps: [ { title: "Fresh step", instruction: "New" } ],
      conditions: [
        {
          condition_field: IncidentCondition::FIELD_INCIDENT_TYPE,
          operator: IncidentCondition::OPERATOR_NOT_ONE_OF,
          values: [ incident_types(:service_outage_ws1).id ]
        }
      ]
    }
    assert_response :redirect

    @runbook.reload
    assert_equal [ "Fresh step" ], @runbook.runbook_steps.ordered.map(&:title)

    condition = @runbook.incident_conditions.sole
    assert_equal IncidentCondition::FIELD_INCIDENT_TYPE, condition.condition_field
    assert_equal IncidentCondition::OPERATOR_NOT_ONE_OF, condition.operator
  end

  test "update with empty conditions clears them" do
    patch runbook_url(@runbook), params: { name: "Existing", conditions: [] }
    assert_response :redirect
    assert_empty @runbook.reload.incident_conditions
  end

  test "destroy deletes a runbook nothing references" do
    assert_difference -> { Runbook.count }, -1 do
      delete runbook_url(@runbook)
    end
    assert_response :redirect
    assert_not Runbook.exists?(@runbook.id)
  end

  test "destroy refuses a runbook attached to incidents" do
    incident = incidents(:active_critical_ws1)
    @runbook.incident_runbooks.create!(incident: incident, workspace: @workspace)

    assert_no_difference -> { Runbook.count } do
      delete runbook_url(@runbook)
    end
    assert_match(/in use by 1 incident/, flash[:alert])
  end

  test "disable then enable round-trips a runbook" do
    patch disable_runbook_url(@runbook)
    assert_not_nil @runbook.reload.deleted_at
    assert_equal "#{@runbook.name} was disabled.", flash[:notice]

    patch enable_runbook_url(@runbook)
    assert_nil @runbook.reload.deleted_at
    assert_equal "#{@runbook.name} was enabled.", flash[:notice]
  end

  test "reorder rewrites positions" do
    other = @workspace.runbooks.create!(name: "Second")
    reversed = @workspace.runbooks.ordered.to_a.reverse

    patch reorder_runbooks_url, params: { ordered_ids: reversed.map(&:id) }

    assert_equal reversed.map(&:id), @workspace.runbooks.ordered.map(&:id)
    assert_equal "Runbook order updated.", flash[:notice]
    assert other.persisted?
  end

  test "non-admin cannot create" do
    sign_in(users(:bob), @workspace)

    assert_no_difference -> { Runbook.count } do
      post runbooks_url(format: :html), params: { name: "Denied" }
    end
    assert_redirected_to dashboard_path
  end

  test "create with blank name surfaces validation errors" do
    assert_no_difference -> { Runbook.count } do
      post runbooks_url(format: :html), params: { name: "" }
    end
    assert_response :redirect
  end

  test "the settings page saves what lets Halon run a runbook, and a later save without a tool clears it" do
    patch runbook_url(@runbook, format: :html), params: {
      aliases: [ "ship it" ],
      inputs: [ { key: "bump", question: "Which version bump?", default: "patch" } ],
      steps: [ { id: @runbook.runbook_steps.first.id, title: "Old step", instruction: "Old", tool: "run_workflow", arguments: { bump: "{{bump}}" } } ],
      watch: { title: "release", steps: [ { label: "Release run", capability: "run_history", resource: "firefight" } ] }
    }
    assert_response :redirect
    assert_equal "Existing was updated.", flash[:notice]

    @runbook.reload
    assert_equal [ "ship it" ], @runbook.aliases
    assert_equal "patch", @runbook.inputs.first["default"]
    assert_equal [ "run_workflow", { "bump" => "{{bump}}" } ], [ @runbook.runbook_steps.first.tool, @runbook.runbook_steps.first.arguments ]
    assert_equal "run_history", @runbook.watch["steps"].first["capability"]

    patch runbook_url(@runbook, format: :html), params: { steps: [ { id: @runbook.runbook_steps.first.id, title: "Old step", instruction: "Old", tool: "" } ], watch: "" }

    @runbook.reload
    assert_nil @runbook.runbook_steps.first.tool
    assert_nil @runbook.watch
    assert_not @runbook.procedure?
  end

  test "a watch that names nothing to check is refused with why" do
    patch runbook_url(@runbook, format: :html), params: { watch: { title: "release" } }

    assert_response :redirect
    assert_nil @runbook.reload.watch
  end
end

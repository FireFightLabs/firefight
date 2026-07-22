require "test_helper"

class RunbooksControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents

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

  test "destroy soft-deletes via deleted_at" do
    delete runbook_url(@runbook)
    assert_response :redirect

    assert_not_nil @runbook.reload.deleted_at
    assert Runbook.exists?(@runbook.id), "Should not hard-delete"
    assert_not @workspace.runbooks.active.exists?(@runbook.id)
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
end

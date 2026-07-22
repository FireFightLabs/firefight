require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "runbooks renders active runbooks with steps and conditions plus option lists" do
    runbook = @workspace.runbooks.create!(name: "Failover", summary: "Fail over the DB")
    runbook.runbook_steps.create!(title: "Promote replica", position: 1)
    runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ incident_severities(:critical_ws1).id ]
    )
    @workspace.runbooks.create!(name: "Archived", deleted_at: Time.current)

    get settings_runbooks_url, headers: inertia_headers
    assert_response :success

    runbooks = inertia_props["runbooks"]
    assert_equal [ "Failover" ], runbooks.map { |r| r["name"] }
    assert_equal [ "Promote replica" ], runbooks.first["steps"].map { |s| s["title"] }
    assert_equal 1, runbooks.first["conditions"].length

    assert inertia_props["incidentTypes"].any?
    assert inertia_props["severities"].any?
  end

  private

  def inertia_props
    JSON.parse(response.body)["props"]
  end
end

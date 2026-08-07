require "test_helper"

class RunbookMatchingTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @critical = @workspace.incident_severities.active.find_by!(slug: "critical")
    @context = IncidentConditionEvaluator.context(severity: @critical.id)
  end

  test "a runbook with no conditions stays off every incident by default" do
    runbook = @workspace.runbooks.create!(name: "Manual only")

    assert_not_includes Runbook.matching(@workspace, @context), runbook
  end

  test "a runbook marked always attach reaches every incident" do
    runbook = @workspace.runbooks.create!(name: "Every incident", always_attach: true)

    assert_includes Runbook.matching(@workspace, @context), runbook
  end

  test "conditions still decide when they are set, whatever the flag says" do
    runbook = @workspace.runbooks.create!(name: "Critical only", always_attach: true)
    runbook.sync_conditions!([
      { condition_field: IncidentCondition::FIELD_SEVERITY,
        operator: IncidentCondition::OPERATOR_ONE_OF,
        values: [ @critical.id ] }
    ])

    assert_includes Runbook.matching(@workspace, @context), runbook

    minor = @workspace.incident_severities.active.find_by!(slug: "minor")
    assert_not_includes Runbook.matching(@workspace, IncidentConditionEvaluator.context(severity: minor.id)), runbook
  end
end

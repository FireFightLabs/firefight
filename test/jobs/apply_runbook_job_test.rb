require "test_helper"

class ApplyRunbookJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @runbook = @workspace.runbooks.create!(name: "Database outage response")
    @runbook.runbook_steps.create!(title: "Check connection pool", position: 1)
    @runbook.runbook_steps.create!(title: "Failover to replica", position: 2)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )

    stub_post_message
    @incident_runbook = RunbookAttachmentService.new(@workspace).attach(
      incident: @incident, runbook: @runbook
    )
  end

  test "applies the runbook via the service" do
    stub_update_message

    ApplyRunbookJob.perform_now(
      workspace_id: @workspace.id,
      incident_runbook_id: @incident_runbook.id,
      user_id: @member.platform_user_id
    )

    @incident_runbook.reload
    assert @incident_runbook.applied?
    assert_equal 2, @incident.incident_actions.count
  end
end

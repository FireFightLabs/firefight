require "test_helper"

class Interactions::ApplyRunbookHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @runbook = @workspace.runbooks.create!(name: "Database outage response")
    @runbook.runbook_steps.create!(title: "Check connection pool", position: 1)

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

  test "enqueues ApplyRunbookJob" do
    assert_enqueued_with(job: ApplyRunbookJob) do
      result = Interactions::ApplyRunbookHandler.execute(build_interaction(@incident_runbook.id))
      assert_nil result
    end
  end

  test "does not enqueue when already applied" do
    @incident_runbook.update!(applied_at: Time.current, applied_by: @member)

    assert_no_enqueued_jobs only: ApplyRunbookJob do
      Interactions::ApplyRunbookHandler.execute(build_interaction(@incident_runbook.id))
    end
  end

  test "handles missing incident runbook silently" do
    assert_no_enqueued_jobs only: ApplyRunbookJob do
      result = Interactions::ApplyRunbookHandler.execute(build_interaction(SecureRandom.uuid))
      assert_nil result
    end
  end

  private

  def build_interaction(incident_runbook_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::APPLY_RUNBOOK,
      action_value: incident_runbook_id,
      trigger_id: "12345.trigger"
    )
  end
end

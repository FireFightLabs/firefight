require "test_helper"

class Interactions::WritePostmortemHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Resolved, write it up",
      is_private: false,
      channel_id: "C_WRITE_PM",
      resolved_at: Time.current,
      source: Incident::SOURCE_SLACK
    )
  end

  test "starts a generation and tells the clicker" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral)
      .with(channel_id: "C_WRITE_PM", user_id: @member.platform_user_id, text: PostmortemGenerationService.started_message(@incident)).once

    assert_enqueued_with(job: PostmortemGenerationJob) do
      assert_nil Interactions::WritePostmortemHandler.execute(build_interaction)
    end
    assert @incident.reload.postmortem.generating?
  end

  test "a blocked entitlement answers with the denial and starts nothing" do
    message = deny_entitlements!("Your trial has ended.")
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(has_entries(text: message)).once

    assert_no_enqueued_jobs do
      Interactions::WritePostmortemHandler.execute(build_interaction)
    end
    assert_nil @incident.reload.postmortem
  end

  test "an incident that already has a postmortem is refused with the reason" do
    Postmortem.start_blank!(@incident, by: @member)
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(has_entries(text: "#{@incident.identifier} already has a postmortem.")).once

    assert_no_enqueued_jobs do
      Interactions::WritePostmortemHandler.execute(build_interaction)
    end
  end

  test "a failed generation can be started again from the button" do
    Postmortem.start_generation!(@incident, by: @member).mark_generation_failed!("TerminalError")
    Slack::WorkspaceAdapter.any_instance.stubs(:post_ephemeral)

    assert_enqueued_with(job: PostmortemGenerationJob) do
      Interactions::WritePostmortemHandler.execute(build_interaction)
    end
    assert @incident.reload.postmortem.generating?
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      channel_id: @incident.channel_id,
      action_id: Identifiers::WRITE_POSTMORTEM,
      action_value: @incident.id
    )
  end
end

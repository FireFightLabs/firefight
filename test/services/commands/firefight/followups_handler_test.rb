require "test_helper"

class Commands::Firefight::FollowupsHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "opens followups list modal in incident channel" do
    stub_open_modal

    Slack::Client.expects(:open_modal).once.returns({ ok: true, view: { id: "V12345678" } })

    result = Commands::Firefight::FollowupsHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns ephemeral error outside incident channel" do
    result = Commands::Firefight::FollowupsHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal "ephemeral", result[:response_type]
    assert_match(/incident channel/, result[:text])
  end

  private

  def build_command(channel_id:)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      text: "followups",
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

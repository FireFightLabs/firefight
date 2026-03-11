require "test_helper"

class Commands::Firefight::InviteHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens invite modal when no users are provided" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:open_invite_responders_modal).with(trigger_id: "12345.trigger", incident: @incident).once

    result = Commands::Firefight::InviteHandler.execute(build_command("invite"))

    assert_nil result
  end

  test "invites mentioned users immediately" do
    service = mock("incident_invite_service")
    IncidentInviteService.expects(:new).with(@workspace).returns(service)
    service.expects(:invite!).with(incident: @incident, user_ids: [ "U11111111", "U22222222" ]).returns({
      invited_user_ids: [ "U11111111", "U22222222" ],
      already_in_channel_user_ids: [],
      failed_invites: []
    })

    result = Commands::Firefight::InviteHandler.execute(build_command("invite <@U11111111> <@U22222222>"))

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "Invited 2 responders"
  end

  test "returns error when not in incident channel" do
    result = Commands::Firefight::InviteHandler.execute(build_command("invite <@U11111111>", channel_id: "C_NOT_INCIDENT"))

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "handles trigger expiration when opening modal" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:open_invite_responders_modal).raises(AdapterError::TriggerExpired.new("expired"))

    result = Commands::Firefight::InviteHandler.execute(build_command("invite"))

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "expired"
  end

  private

  def build_command(text, channel_id: @incident.channel_id)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: text,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

require "test_helper"

class Commands::InviteRespondersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens invite modal when text has no target tokens" do
    Slack::Modals::Invite.expects(:build).with(@incident).returns({ type: "modal" })
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:open_modal).with(trigger_id: "12345.trigger", view: { type: "modal" }).once

    assert_no_enqueued_jobs only: IncidentInviteJob do
      result = Commands::InviteResponders.execute(build_command("invite"))
      assert_nil result
    end
  end

  test "enqueues IncidentInviteJob when text has target tokens" do
    assert_enqueued_with(
      job: IncidentInviteJob,
      args: [ { workspace_id: @workspace.id, incident_id: @incident.id, text: "invite <@U11111111>", channel_id: @incident.channel_id, user_id: "U12345678" } ]
    ) do
      result = Commands::InviteResponders.execute(build_command("invite <@U11111111>"))

      assert_equal Command::EPHEMERAL, result[:response_type]
      assert_includes result[:text], "Inviting"
    end
  end

  test "enqueues job for bare @handle text" do
    assert_enqueued_jobs 1, only: IncidentInviteJob do
      Commands::InviteResponders.execute(build_command("invite @alice"))
    end
  end

  test "enqueues job for raw user id" do
    assert_enqueued_jobs 1, only: IncidentInviteJob do
      Commands::InviteResponders.execute(build_command("invite U12345678"))
    end
  end

  test "returns error when not in incident channel" do
    result = Commands::InviteResponders.execute(build_command("invite <@U11111111>", channel_id: "C_NOT_INCIDENT"))

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "invite <@U11111111>",
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::InviteResponders.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  test "handles trigger expiration when opening modal" do
    Slack::Modals::Invite.expects(:build).with(@incident).returns({ type: "modal" })
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:open_modal).raises(AdapterError::TriggerExpired.new("expired"))

    result = Commands::InviteResponders.execute(build_command("invite"))

    assert_equal Command::EPHEMERAL, result[:response_type]
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

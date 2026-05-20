require "test_helper"

class Commands::CloseHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens close modal in incident channel" do
    CloseModalOpener.expects(:open).with(
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: "U12345678"
    ).once

    result = Commands::CloseHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in incident channel" do
    result = Commands::CloseHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_CLOSE,
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::CloseHandler.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  test "handles trigger expiration" do
    CloseModalOpener.expects(:open).raises(AdapterError::TriggerExpired.new("expired"))

    result = Commands::CloseHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "expired"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_CLOSE,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

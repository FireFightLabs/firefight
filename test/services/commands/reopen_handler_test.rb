require "test_helper"

class Commands::ReopenHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @resolved_status = incident_statuses(:resolved_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_CLOSED_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
  end

  test "opens reopen modal for closed incident" do
    stub_post_message
    stub_open_modal

    result = Commands::ReopenHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in closed incident channel" do
    result = Commands::ReopenHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "closed incident channel"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_REOPEN,
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::ReopenHandler.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  test "handles trigger expiration" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError)
    stub_delete_message

    result = Commands::ReopenHandler.execute(
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
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_REOPEN,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

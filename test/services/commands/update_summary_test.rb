require "test_helper"

class Commands::UpdateSummaryTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens summary modal in incident channel" do
    stub_post_message
    stub_open_modal

    result = Commands::UpdateSummary.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in incident channel" do
    result = Commands::UpdateSummary.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "handles trigger expiration" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    stub_delete_message

    result = Commands::UpdateSummary.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "expired"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_SUMMARY,
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::UpdateSummary.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_SUMMARY,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

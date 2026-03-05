require "test_helper"

class Commands::Firefight::LeadHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens lead modal in incident channel" do
    stub_open_modal

    result = Commands::Firefight::LeadHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in incident channel" do
    result = Commands::Firefight::LeadHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "handles trigger expiration" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))

    result = Commands::Firefight::LeadHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "expired"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "lead",
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::Firefight::LeadHandler.execute(command)

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: "lead",
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

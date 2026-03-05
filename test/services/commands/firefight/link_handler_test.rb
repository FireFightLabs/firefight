require "test_helper"

class Commands::Firefight::LinkHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens link modal in incident channel" do
    stub_open_modal

    result = Commands::Firefight::LinkHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in incident channel" do
    result = Commands::Firefight::LinkHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "handles trigger expiration" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))

    result = Commands::Firefight::LinkHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_equal "ephemeral", result[:response_type]
    assert_includes result[:text], "expired"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: "link",
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

require "test_helper"

class Commands::Firefight::TimelineHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "returns timeline from incident events" do
    response = Commands::Firefight::TimelineHandler.execute(build_command(channel_id: @incident.channel_id))

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "*Timeline for #{@incident.identifier}*"
    assert_includes response[:text], "Incident declared"
  end

  test "returns error when command is outside incident channel" do
    response = Commands::Firefight::TimelineHandler.execute(build_command(channel_id: "C_NOT_INCIDENT"))

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "incident channel"
  end

  test "returns workspace error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "timeline",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    response = Commands::Firefight::TimelineHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Workspace not found"
  end

  private

  def build_command(channel_id:)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: "timeline",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end

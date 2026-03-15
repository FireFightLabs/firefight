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

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Timeline for #{@incident.identifier}"
    assert_equal "header", response[:blocks].first[:type]
    rendered = response[:blocks].filter_map { |block| block.dig(:text, :text) }
    assert rendered.any? { |text| text.include?("Incident declared") }
  end

  test "includes load more button when more events are available" do
    member = workspace_memberships(:alice_workspace_one)
    20.times do
      @incident.incident_events.create!(event_type: IncidentEvent::INCIDENT_UPDATED, user: member)
    end

    response = Commands::Firefight::TimelineHandler.build_response(@incident, limit: 1)

    actions_block = response[:blocks].find { |block| block[:type] == "actions" }
    refute_nil actions_block
    button = actions_block[:elements].first
    assert_equal Identifiers::LOAD_MORE_TIMELINE, button[:action_id]
  end

  test "returns error when command is outside incident channel" do
    response = Commands::Firefight::TimelineHandler.execute(build_command(channel_id: "C_NOT_INCIDENT"))

    assert_equal Command::EPHEMERAL, response[:response_type]
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

    assert_equal Command::EPHEMERAL, response[:response_type]
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

require "test_helper"

class Commands::ShowTimelineTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens timeline modal from incident channel" do
    Slack::Client.expects(:open_modal).with do |args|
      view = args[:view]
      view[:type] == "modal" &&
        view[:callback_id] == Identifiers::TIMELINE_MODAL &&
        view[:blocks].any? { |b| b.dig(:text, :text)&.include?("Incident declared") }
    end.returns({ ok: true })

    result = Commands::ShowTimeline.execute(build_command(channel_id: @incident.channel_id))

    assert_nil result
  end

  test "includes load more button when more events are available" do
    member = workspace_memberships(:alice_workspace_one)
    20.times do
      @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, actor: member)
    end

    view = @workspace.adapter.build_timeline_view(@incident, limit: 15)

    actions_block = view[:blocks].find { |block| block[:type] == "actions" }
    refute_nil actions_block
    button = actions_block[:elements].first
    assert_equal Identifiers::LOAD_MORE_TIMELINE, button[:action_id]
  end

  test "omits load more button once the modal cap is reached" do
    member = workspace_memberships(:alice_workspace_one)
    (50 - @incident.incident_events.count).times do
      @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, actor: member)
    end

    view = @workspace.adapter.build_timeline_view(@incident, limit: Slack::WorkspaceAdapter::IncidentMessaging::TIMELINE_MAX_EVENTS)

    assert_nil view[:blocks].find { |block| block[:type] == "actions" }
    context_block = view[:blocks].find do |block|
      block[:type] == "context" && block.dig(:elements, 0, :text)&.include?("Showing latest 45 of 50 events")
    end
    refute_nil context_block
  end

  test "returns error when command is outside incident channel" do
    response = Commands::ShowTimeline.execute(build_command(channel_id: "C_NOT_INCIDENT"))

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "incident channel"
  end

  test "returns workspace error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_TIMELINE,
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    response = Commands::ShowTimeline.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Workspace not found"
  end

  private

  def build_command(channel_id:)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_TIMELINE,
      channel_id: channel_id,
      trigger_id: "trigger_123",
      metadata: { command: "/ff" }
    )
  end
end

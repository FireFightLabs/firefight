require "test_helper"

class Commands::ShowTimelineTest < ActiveSupport::TestCase
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

  test "shows no pager when the whole timeline fits one window" do
    fill_timeline_to(20)

    view = @workspace.adapter.build_timeline_view(@incident)

    assert_nil view[:blocks].find { |block| block[:type] == "actions" }
    assert_nil caption(view)
  end

  test "offers older but not newer on the first window" do
    fill_timeline_to(60)

    view = @workspace.adapter.build_timeline_view(@incident)

    assert_equal [ "Older" ], page_button_labels(view)
    assert_equal 45, page_offsets(view).first
    assert_equal "Showing events 16 to 60 of 60", caption(view)
  end

  test "offers newer but not older on the oldest window" do
    fill_timeline_to(60)

    view = @workspace.adapter.build_timeline_view(@incident, offset: 45)

    assert_equal [ "Newer" ], page_button_labels(view)
    assert_equal 0, page_offsets(view).first
    assert_equal "Showing events 1 to 15 of 60", caption(view)
  end

  test "offers both directions on a middle window" do
    fill_timeline_to(140)

    view = @workspace.adapter.build_timeline_view(@incident, offset: 45)

    assert_equal [ "Older", "Newer" ], page_button_labels(view)
    assert_equal [ 90, 0 ], page_offsets(view)
    assert_equal "Showing events 51 to 95 of 140", caption(view)
  end

  test "never renders more blocks than a modal holds" do
    fill_timeline_to(140)

    view = @workspace.adapter.build_timeline_view(@incident)

    assert_operator view[:blocks].size, :<=, 100
  end

  test "clamps an offset past the end of the timeline onto the oldest event" do
    fill_timeline_to(60)

    view = @workspace.adapter.build_timeline_view(@incident, offset: 900)

    assert_equal "Showing events 1 to 1 of 60", caption(view)
  end

  test "links to the dashboard timeline when a host is configured" do
    fill_timeline_to(60)

    view = with_app_host { @workspace.adapter.build_timeline_view(@incident) }

    link = view[:blocks].find { |block| block[:type] == "actions" }[:elements].last
    assert_equal "View full timeline", link.dig(:text, :text)
    assert_equal "https://app.example.com/app/incidents/#{@incident.id}", link[:url]
  end

  test "omits the dashboard link when no host is configured" do
    fill_timeline_to(60)

    view = @workspace.adapter.build_timeline_view(@incident)

    assert_empty view[:blocks].find { |block| block[:type] == "actions" }[:elements].filter_map { |element| element[:url] }
  end

  test "returns error when command is outside incident channel" do
    response = Commands::ShowTimeline.execute(build_command(channel_id: "C_NOT_INCIDENT"))

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "incident channel"
  end

  private

  def fill_timeline_to(count)
    member = workspace_memberships(:alice_workspace_one)
    (count - @incident.incident_events.count).times do
      @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, actor: member)
    end
  end

  def page_buttons(view)
    actions_block = view[:blocks].find { |block| block[:type] == "actions" }
    return [] unless actions_block

    actions_block[:elements].select { |element| element[:action_id] == Identifiers::TIMELINE_PAGE }
  end

  def page_button_labels(view)
    page_buttons(view).map { |button| button.dig(:text, :text) }
  end

  def page_offsets(view)
    page_buttons(view).map { |button| JSON.parse(button[:value])["offset"] }
  end

  def caption(view)
    context_block = view[:blocks].reverse.find { |block| block[:type] == "context" }
    text = context_block&.dig(:elements, 0, :text)
    text&.start_with?("Showing events") ? text : nil
  end

  def with_app_host
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "app.example.com"
    yield
  ensure
    ENV["APP_HOST"] = previous
  end

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

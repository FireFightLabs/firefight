require "test_helper"

class Interactions::TimelinePageHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "updates the modal with the requested window" do
    fill_timeline_to(60)

    Slack::Client.expects(:update_modal).with do |args|
      args[:view_id] == "V_TIMELINE" &&
        args[:view][:blocks].any? { |block| caption(block)&.include?("Showing events 1 to 15 of 60") }
    end.returns({ ok: true })

    assert_nil Interactions::TimelinePageHandler.execute(build_interaction(offset: 45))
  end

  test "renders the newest window for a payload from a pre-pager modal" do
    fill_timeline_to(60)

    Slack::Client.expects(:update_modal).with do |args|
      args[:view][:blocks].any? { |block| caption(block)&.include?("Showing events 16 to 60 of 60") }
    end.returns({ ok: true })

    interaction = build_interaction(
      action_id: Identifiers::LOAD_MORE_TIMELINE,
      action_value: { incident_id: @incident.id, limit: 30 }.to_json
    )

    assert_nil Interactions::TimelinePageHandler.execute(interaction)
  end

  test "clamps an offset that outruns the timeline" do
    fill_timeline_to(60)

    Slack::Client.expects(:update_modal).with do |args|
      args[:view][:blocks].any? { |block| caption(block)&.include?("of 60") }
    end.returns({ ok: true })

    assert_nil Interactions::TimelinePageHandler.execute(build_interaction(offset: 900))
  end

  test "returns nil when view_id is missing" do
    assert_nil Interactions::TimelinePageHandler.execute(build_interaction(view: nil))
  end

  private

  def fill_timeline_to(count)
    (count - @incident.incident_events.count).times do
      @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, actor: @member)
    end
  end

  def caption(block)
    block[:type] == "context" ? block.dig(:elements, 0, :text) : nil
  end

  def build_interaction(offset: 0, **overrides)
    defaults = {
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      channel_id: @incident.channel_id,
      action_id: Identifiers::TIMELINE_PAGE,
      action_value: { incident_id: @incident.id, offset: offset }.to_json,
      view: { "id" => "V_TIMELINE" }
    }

    Interaction.new(defaults.merge(overrides))
  end
end

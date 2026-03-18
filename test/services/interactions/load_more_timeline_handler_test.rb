require "test_helper"

class Interactions::LoadMoreTimelineHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "updates timeline modal with more events" do
    Slack::Client.expects(:update_modal).with do |args|
      args[:view_id] == "V_TIMELINE" &&
        args[:view][:type] == "modal" &&
        args[:view][:blocks].present?
    end.returns({ ok: true })

    result = Interactions::LoadMoreTimelineHandler.execute(build_interaction)

    assert_nil result
  end

  test "returns nil when view_id is missing" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      channel_id: @incident.channel_id,
      action_id: Identifiers::LOAD_MORE_TIMELINE,
      action_value: { incident_id: @incident.id, limit: 30 }.to_json,
      view: nil
    )

    result = Interactions::LoadMoreTimelineHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction(limit: 30)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      channel_id: @incident.channel_id,
      action_id: Identifiers::LOAD_MORE_TIMELINE,
      action_value: { incident_id: @incident.id, limit: limit }.to_json,
      view: { "id" => "V_TIMELINE" }
    )
  end
end

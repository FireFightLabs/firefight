require "test_helper"

class Interactions::LoadMoreTimelineHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "posts expanded timeline ephemerally" do
    Slack::Client.expects(:post_ephemeral).with do |args|
      args[:channel] == @incident.channel_id &&
        args[:user] == @member.platform_user_id &&
        args[:blocks].present?
    end.returns({ ok: true })

    result = Interactions::LoadMoreTimelineHandler.execute(build_interaction)

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
      action_value: { incident_id: @incident.id, limit: limit }.to_json
    )
  end
end

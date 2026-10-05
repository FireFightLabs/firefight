require "test_helper"

class Interactions::CreateActionIssueHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @linear = connect_tracker!(@workspace, provider: "linear")
    stub_post_message
    stub_update_message
    stub_get_permalink
    @item = IncidentActionService.new(@workspace).create_action(
      incident: @incident, created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the password"
    )
  end

  def click(item)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @alice.platform_user_id,
                    channel_id: @incident.channel_id, action_id: Identifiers::CREATE_ACTION_ISSUE, action_value: item.id, trigger_id: "1.trigger")
  end

  test "Create issue opens the item's issue as whoever clicked" do
    sync_with!(@workspace, @linear)
    tracker_answers("save_issue" => json_answer({ "id" => "ENG-1", "title" => "Rotate the password", "url" => "https://linear.app/a/issue/ENG-1/x" }))

    perform_enqueued_jobs { assert_nil Interactions::CreateActionIssueHandler.execute(click(@item)) }

    assert_equal "ENG-1", @item.reload.external_key
    assert Ability::Invocation.exists?(action_key: "linear.save_issue", principal_id: @alice.id)
  end

  test "why the issue cannot be opened is said to whoever clicked" do
    sync_with!(@workspace, @linear, target: {})
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(has_entries(user_id: @alice.platform_user_id, text: "Say which team new issues go to."))

    Interactions::CreateActionIssueHandler.execute(click(@item))
  end
end

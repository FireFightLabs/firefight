require "test_helper"

class Mcp::Tools::CreateActionItemIssueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @linear = connect_tracker!(@workspace, provider: "linear")
    @item = @incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the password")
    tracker_answers("save_issue" => json_answer({ "id" => "ENG-1", "title" => "Rotate the password", "url" => "https://linear.app/a/issue/ENG-1/x" }))
  end

  def ask = Mcp::Tools::CreateActionItemIssue.perform_with_principal(workspace: @workspace, principal: @alice,
                                                                       args: { incident: @incident.identifier, action_item: @item.id })

  test "an agent asks for an item's issue, which is opened as it and shows on the item" do
    sync_with!(@workspace, @linear)

    response = perform_enqueued_jobs { ask }

    assert_equal "ENG-1", response.structured_content[:external_key]
    assert_equal "ENG-1", @item.reload.external_key
    item = Mcp::Tools::GetIncident.action_items(@incident).find { |each| each[:id] == @item.id }
    assert_equal [ "ENG-1", "https://linear.app/a/issue/ENG-1/x" ], [ item[:external_key], item[:external_url] ]
  end

  test "asking where the workspace opens no issues is refused with the reason" do
    response = ask

    assert response.error?
    assert_match "Choose an issue tracker under Settings, Workspace", response.content.first[:text]
  end
end

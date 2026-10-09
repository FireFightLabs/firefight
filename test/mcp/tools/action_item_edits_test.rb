require "test_helper"

class Mcp::Tools::ActionItemEditsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @action = @incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Restart",
                                                 assignee: @alice, status: IncidentAction::STATUS_IN_PROGRESS)
  end

  def call(tool, **args)
    tool.perform_with_principal(workspace: @workspace, principal: @alice, args: { incident: @incident.identifier, action_item: @action.id, **args })
  end

  test "an agent renames, lets go of and reopens an item, and is told why when it cannot" do
    assert_equal "Restart every worker", call(Mcp::Tools::RenameActionItem, description: "Restart every worker").structured_content[:description]

    assert_equal IncidentAction::STATUS_OPEN, call(Mcp::Tools::UnassignActionItem).structured_content[:status]
    refused = call(Mcp::Tools::UnassignActionItem)
    assert refused.error?
    assert_equal "Nobody holds that item.", refused.content.first[:text]

    assert call(Mcp::Tools::ReopenActionItem).error?
    @action.update!(status: IncidentAction::STATUS_DONE)
    assert_equal IncidentAction::STATUS_OPEN, call(Mcp::Tools::ReopenActionItem).structured_content[:status]
  end

  test "a title past 3,000 characters is refused with how long it is" do
    refused = call(Mcp::Tools::RenameActionItem, description: "a" * 3_001)

    assert refused.error?
    assert_equal "This is a little long. Please shorten it to 3,000 characters or fewer (it's 3,001 now).", refused.content.first[:text]
    assert_equal "Restart", @action.reload.description
  end

  test "the agent in a chat is offered them with the other item tools" do
    tools = Chat::Tools::Groups::FIREFIGHT.find { |group| group.key == Chat::Tools::Groups::FOLLOW_UPS }.tools
    assert_includes tools, Mcp::Tools::RENAME_ACTION_ITEM
    assert_includes tools, Mcp::Tools::REOPEN_ACTION_ITEM
    assert_includes tools, Mcp::Tools::UNASSIGN_ACTION_ITEM
  end
end

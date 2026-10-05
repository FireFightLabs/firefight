require "test_helper"

class Mcp::ToolDispatcherTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "one of Firefight's own tools answering with an error is ledgered as an error with what it said" do
    Mcp::Tools::CompleteActionItem.stubs(:perform_with_principal).returns(Mcp::ToolDispatcher.error_response("This action item is already done."))

    response = Mcp::ToolDispatcher.call(tool: Mcp::Tools::CompleteActionItem, server_context: { workspace: @workspace, principal: @alice },
                                        args: { incident: "INC-1", action_item: "1" })

    assert response.error?
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "incidents.update", principal: @alice)
    assert_equal [ AbilityGateway::SOURCE_MCP, Ability::Invocation::OUTCOME_ERROR, "This action item is already done." ],
                 [ invocation.source, invocation.outcome, invocation.error_summary ]
  end
end

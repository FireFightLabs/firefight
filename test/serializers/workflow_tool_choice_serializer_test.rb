require "test_helper"

class WorkflowToolChoiceSerializerTest < ActiveSupport::TestCase
  include ManyToolsHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Look around")
  end

  test "what each tool needs granted is worked out in the same queries however many tools the workspace has" do
    connection_with_tools(@workspace, 3, name: "Few")
    few_queries = queries_made { serialized }
    connection_with_tools(@workspace, 40, name: "Many")
    many_queries = queries_made { serialized }

    assert_operator many_queries, :<=, few_queries + 4, "40 more tools made #{many_queries - few_queries} more queries"
  end

  test "Firefight's own tools look their abilities up together rather than one query each" do
    workspace = Workspace.find(@workspace.id)
    choices = Chat::Tools::Choices.tools(workspace)
    own = choices.count { |choice| DefinedWorkflow::Reach.firefight_tool(choice.name) }
    queries = queries_made { WorkflowToolChoiceSerializer.many(choices, workflow: Workflow.find(@workflow.id)) }

    assert_operator own, :>, 40
    assert_operator queries, :<, 20, "#{own} of Firefight's own tools took #{queries} queries"
  end

  test "a read names its connection's read pack and a change its own ability, as before" do
    connection_with_tools(@workspace, 2, name: "Pair")
    choices = serialized.index_by { |choice| choice[:name] }

    assert_equal "Needs read Pair (Custom MCP server), which publishing grants to the workflow.", choices.fetch("pair_tool_0")[:grantNeeded]
    assert_equal "Needs pair (Custom MCP server): tool 1, which publishing grants to the workflow.", choices.fetch("pair_tool_1")[:grantNeeded]
  end

  private

  def serialized
    workspace = Workspace.find(@workspace.id)
    WorkflowToolChoiceSerializer.many(Chat::Tools::Choices.tools(workspace), workflow: Workflow.find(@workflow.id)).map(&:symbolize_keys)
  end
end

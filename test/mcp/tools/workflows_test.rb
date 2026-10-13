require "test_helper"

module Mcp
  module Tools
    # Workflows over MCP: listed, made and run only where the workspace has workflows, each through the gateway.
    class WorkflowsTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
        WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
      end

      def call(tool, principal, args) = ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)

      def spec = { name: "Look around", steps: [ { name: "look", kind: "call_tool", config: { tool: SEARCH_INCIDENTS, arguments: {} } } ] }

      test "nothing about workflows is listed, offered to Halon or run without the flag" do
        FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

        listed = Mcp::Tools.for_workspace(@workspace).map(&:name_value)
        [ LIST_WORKFLOWS, CREATE_WORKFLOW, RUN_WORKFLOW, UPDATE_WORKFLOW_SETTINGS ].each { |name| assert_not_includes listed, name }
        offered = Chat::Tools.firefight_entries(Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @admin), asker: @admin)).map { |entry| entry.name.to_s }
        assert_not_includes offered, UPDATE_WORKFLOW_SETTINGS
        answer = call(ListWorkflows, @admin, {})
        assert answer.error?
        assert_match "There is no tool called list_workflows", answer.content.first[:text]
      end

      test "an admin makes one live, and a member's waits as a draft with the admins asked" do
        made = call(CreateWorkflow, @admin, spec)
        assert_not made.error?, made.content.first[:text]
        assert_equal true, made.structured_content[:published]

        drafted = call(CreateWorkflow, @member, spec.merge(name: "Member's"))
        assert_equal false, drafted.structured_content[:published]
        assert_match "Asked", drafted.structured_content[:said]
        assert @workspace.workflows.find_by!(name: "Member's").publish_requests.waiting.exists?
      end

      test "a run starts by name, and the list says how it stands" do
        call(CreateWorkflow, @admin, spec)

        ran = nil
        perform_enqueued_jobs { ran = call(RunWorkflow, @member, { workflow: "look_around" }) }
        assert_not ran.error?, ran.content.first[:text]
        assert_match "/halon/workflows/", ran.structured_content[:page]

        listed = call(ListWorkflows, @member, {}).structured_content[:workflows]
        assert_equal [ "Look around" ], listed.map { |row| row[:name] }
        assert_equal Workflow::Run::STATUS_SUCCEEDED, listed.first[:last_run][:status]
      end

      test "only an admin sets how long runs keep their details" do
        assert call(UpdateWorkflowSettings, @member, { workflow_run_retention_days: 30 }).error?
        assert_not call(UpdateWorkflowSettings, @admin, { workflow_run_retention_days: 30 }).error?
        assert_equal 30, @workspace.reload.workflow_run_retention_days
      end
    end
  end
end

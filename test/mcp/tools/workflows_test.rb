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
        [ LIST_WORKFLOWS, CREATE_WORKFLOW, RUN_WORKFLOW, UPDATE_WORKFLOW_SETTINGS, UPDATE_WORKFLOW ].each { |name| assert_not_includes listed, name }
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

      test "publishing held for an approval answers with the draft made, never as a call to retry" do
        PolicyRule::ApprovalConditions.stubs(:errors_for).returns([])
        AbilityGateway.stubs(:approval_requirement).returns(nil)
        AbilityGateway.stubs(:approval_requirement).with { |*given| given[2] == Workflow::PUBLISH_KEY }.returns({ "role" => "admin", "count" => 1 })

        made = call(CreateWorkflow, @admin, spec)

        assert_not made.error?, made.content.first[:text]
        assert_equal false, made.structured_content[:published]
        assert_match "Publishing it is held for an approval", made.structured_content[:said]
        assert_equal 1, @workspace.workflows.where(name: "Look around").count
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

      test "a workflow is made with its most runs an hour, and the list says it and how many were skipped" do
        made = call(CreateWorkflow, @admin, spec.merge(runs_per_hour: 20))
        assert_not made.error?, made.content.first[:text]
        workflow = @workspace.workflows.find_by!(name: "Look around")
        assert_equal 20, workflow.runs_per_hour
        workflow.run_skipped!

        listed = call(ListWorkflows, @member, {}).structured_content[:workflows].sole
        assert_equal 20, listed[:runs_per_hour]
        assert_equal 1, listed[:skipped_runs_last_week]
      end

      test "a most runs an hour out of bounds is refused with why" do
        made = call(CreateWorkflow, @admin, spec.merge(runs_per_hour: 0))

        assert made.error?
        assert_match "Runs per hour", made.content.first[:text]
        assert_not @workspace.workflows.exists?(name: "Look around")
      end

      test "an admin changes a workflow's settings by name, and only what is given changes" do
        call(CreateWorkflow, @admin, spec)
        workflow = @workspace.workflows.find_by!(name: "Look around")
        workflow.update!(all_clear: true)

        changed = call(UpdateWorkflow, @admin, { workflow: "Look around", runs_per_hour: 30, cost_cap_cents: 150, freeze_behaviour: Workflow::FREEZE_WAIT })

        assert_not changed.error?, changed.content.first[:text]
        assert_equal [ 30, 150, Workflow::FREEZE_WAIT, true ], workflow.reload.values_at(:runs_per_hour, :cost_cap_cents, :freeze_behaviour, :all_clear)
        assert_equal 30, changed.structured_content[:workflow][:runs_per_hour]
        assert_equal "Look around was updated.", changed.structured_content[:said]

        cleared = call(UpdateWorkflow, @admin, { workflow: workflow.slug, cost_cap_cents: nil })
        assert_not cleared.error?
        assert_nil workflow.reload.cost_cap_cents
      end

      test "changing a workflow's settings is refused for a member, for a value the page refuses, and for a workflow that is not there" do
        call(CreateWorkflow, @admin, spec)
        workflow = @workspace.workflows.find_by!(name: "Look around")

        assert call(UpdateWorkflow, @member, { workflow: "Look around", runs_per_hour: 5 }).error?
        invalid = call(UpdateWorkflow, @admin, { workflow: "Look around", runs_per_hour: 5_000 })
        assert invalid.error?
        assert_match "Runs per hour", invalid.content.first[:text]
        missing = call(UpdateWorkflow, @admin, { workflow: "Nothing like it", runs_per_hour: 5 })
        assert missing.error?
        assert_match "No workflow is called Nothing like it", missing.content.first[:text]
        assert_equal 100, workflow.reload.runs_per_hour
      end

      def halon_tool(member, name)
        turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: member), asker: member)
        Chat::Tools.firefight_entries(turn).find { |entry| entry.name.to_s == name }&.tool
      end

      test "Halon may change a workflow's settings when asked, only once the person confirms it in the chat" do
        tool = halon_tool(@admin, UPDATE_WORKFLOW)

        assert tool, "Halon is offered update_workflow"
        assert tool.requires_approval?, "the change waits for the person's confirmation, never made silently"
        assert_includes tool.parameters_schema.dig("properties").keys, Chat::Tools::INTENT_ARG
      end

      test "Halon changes a workflow's settings through the gateway as the person, and a member without the grant is not offered it" do
        call(CreateWorkflow, @admin, spec)
        workflow = @workspace.workflows.find_by!(name: "Look around")

        assert_nil halon_tool(@member, UPDATE_WORKFLOW)

        halon_tool(@admin, UPDATE_WORKFLOW).call(workflow: "Look around", runs_per_hour: 5)
        assert_equal 5, workflow.reload.runs_per_hour
        assert Ability::Invocation.exists?(workspace: @workspace, action_key: Workflow::PUBLISH_KEY, source: AbilityGateway::SOURCE_CONVERSATION)
      end

      test "only an admin sets how long runs keep their details" do
        assert call(UpdateWorkflowSettings, @member, { workflow_run_retention_days: 30 }).error?
        assert_not call(UpdateWorkflowSettings, @admin, { workflow_run_retention_days: 30 }).error?
        assert_equal 30, @workspace.reload.workflow_run_retention_days
      end
    end
  end
end

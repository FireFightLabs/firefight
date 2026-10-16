require "test_helper"

module Mcp
  module Tools
    # The runbook tools keep their names and answers where the workspace has workflows: a runbook is a guide whose
    # steps are its checklist, and what it runs is read from and written to the workflow it links.
    class RunbookWorkflowsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
      end

      def call(tool, principal, args) = ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)

      def release_args
        {
          name: "Release Firefight", aliases: [ "ship it" ],
          inputs: [ { key: "bump", question: "Which version bump?", default: "patch" } ],
          steps: [ { title: "Look for past releases", tool: SEARCH_INCIDENTS, arguments: { query: "release {{bump}}" } },
                   { title: "Tell the team", instruction: "In #releases." } ],
          watch: { title: "release", steps: [ { label: "Incidents", tool: SEARCH_INCIDENTS, arguments: { query: "{{bump}}" }, goal: "none open" } ] }
        }
      end

      test "upsert_runbook keeps every step as the checklist and writes what it runs into a workflow it links, published by an admin" do
        answer = call(UpsertRunbook, @admin, release_args)
        assert_not answer.error?, answer.content.first[:text]

        runbook = @workspace.runbooks.find_by!(slug: "release_firefight")
        assert_equal [ "Look for past releases", "Tell the team" ], runbook.runbook_steps.map(&:title)
        assert runbook.runbook_steps.none?(&:tool?)
        assert_equal [], runbook.inputs
        assert_nil runbook.watch

        workflow = runbook.workflow
        assert workflow.live?
        version = workflow.live_version
        assert_equal [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], version.trigger["inputs"]
        assert_equal [ "look_for_past_releases", "watch" ], version.steps.map { |step| step["name"] }
        assert_equal({ "query" => "release {{inputs.bump}}" }, version.steps.first.dig("config", "arguments"))

        said = answer.structured_content
        assert_equal true, said[:runnable]
        assert_equal Workflow::STATE_LIVE, said.dig(:workflow, :state)
        assert_equal "Release Firefight was published.", said.dig(:workflow, :said)
      end

      test "a member's write waits as a draft and the admins are asked to publish it" do
        Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_CREATE)) })
        answer = call(UpsertRunbook, @member, release_args)
        assert_not answer.error?, answer.content.first[:text]

        workflow = @workspace.runbooks.find_by!(slug: "release_firefight").workflow
        assert_not workflow.live?
        assert_equal @member, workflow.draft.author
        assert_equal false, answer.structured_content[:runnable]
        assert_match "Asked", answer.structured_content.dig(:workflow, :said)
      end

      test "a step that changes something waits as a draft until it says how to undo it" do
        args = release_args.merge(steps: [ { title: "Note it", tool: CREATE_ACTION_ITEM, arguments: { incident: "INC-1", description: "Release" } } ])

        answer = call(UpsertRunbook, @admin, args)

        assert_not answer.error?
        assert_match "waits as a draft, since it cannot be published yet. note_it changes something, so it needs its undo", answer.structured_content.dig(:workflow, :said)

        args[:steps].first[:undo] = "Delete the action item."
        again = call(UpsertRunbook, @admin, args.merge(slug: "release_firefight"))
        assert_equal "Release Firefight was published.", again.structured_content.dig(:workflow, :said)
        assert_equal "Delete the action item.", @workspace.workflows.find_by!(slug: "release_firefight").live_version.steps.first.dig("config", "undo")
      end

      test "get_runbook answers the checklist, and the inputs, watch and steps it runs from its workflow" do
        call(UpsertRunbook, @admin, release_args)

        got = call(GetRunbook, @admin, { slug: "release_firefight" }).structured_content

        assert_equal [ { position: 1, title: "Look for past releases" }, { position: 2, title: "Tell the team", instruction: "In #releases." } ], got[:steps]
        assert_equal [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], got[:inputs]
        assert_equal "{{bump}}", got[:watch]["steps"].first.dig("arguments", "query")
        assert_equal [ { "title" => "look_for_past_releases", "tool" => SEARCH_INCIDENTS, "arguments" => { "query" => "release {{bump}}" } } ], got.dig(:workflow, :steps)
        assert_equal Workflow::Links.page(@workspace.workflows.find_by!(slug: "release_firefight")), got.dig(:workflow, :page)
      end

      test "writing back what get_runbook read changes the checklist and leaves the workflow alone" do
        call(UpsertRunbook, @admin, release_args)
        workflow = @workspace.workflows.find_by!(slug: "release_firefight")
        got = call(GetRunbook, @admin, { slug: "release_firefight" }).structured_content

        answer = call(UpsertRunbook, @admin, { slug: "release_firefight", steps: got[:steps] + [ { title: "Celebrate" } ], inputs: got[:inputs], watch: got[:watch] })

        assert_not answer.error?
        assert_nil workflow.reload.draft, "nothing it runs changed, so no draft was opened"
        assert_equal [ "Look for past releases", "Tell the team", "Celebrate" ], @workspace.runbooks.find_by!(slug: "release_firefight").runbook_steps.map(&:title)
      end

      test "a workflow changed on its page beyond what a runbook can say is not written over" do
        call(UpsertRunbook, @admin, release_args)
        workflow = @workspace.workflows.find_by!(slug: "release_firefight")
        workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, by: @admin,
                       payload: { step_id: workflow.live_version.steps.first["id"], changes: { "retry" => { "max_attempts" => 3 } } })

        answer = call(UpsertRunbook, @admin, { slug: "release_firefight", inputs: [] })

        assert answer.error?
        assert_match "Release Firefight was changed on its page beyond steps that call a tool and a watch, so change what it runs there.", answer.content.first[:text]
      end

      test "search_runbooks says which runbooks run their workflow now" do
        call(UpsertRunbook, @admin, release_args)
        @workspace.runbooks.create!(name: "Database failover")

        found = call(SearchRunbooks, @admin, {}).structured_content[:runbooks].index_by { |runbook| runbook[:slug] }

        assert_equal true, found["release_firefight"][:runnable]
        assert_equal({ name: "Release Firefight", state: Workflow::STATE_LIVE }, found["release_firefight"][:workflow])
        assert_equal false, found["database_failover"][:runnable]
        assert_not found["database_failover"].key?(:workflow)
      end

      test "attach_runbook and claim_runbook_step work on a runbook whose steps moved, its former tool step included" do
        call(UpsertRunbook, @admin, release_args)
        incident = incidents(:active_critical_ws1)
        WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_runbook_message).returns(message_id: "1.2")
        WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:update_runbook_message)

        attached = call(AttachRunbook, @admin, { incident: incident.identifier, runbook: "release_firefight" })
        assert_not attached.error?, attached.content.first[:text]
        assert_equal 2, attached.structured_content[:steps_count]

        attachment = incident.incident_runbooks.sole
        step = attachment.runbook.runbook_steps.first
        claimed = call(ClaimRunbookStep, @admin, { incident: incident.identifier, runbook: attachment.id, step: step.id })
        assert_not claimed.error?, claimed.content.first[:text]
        assert incident.incident_actions.active.exists?(runbook_step: step)
      end
    end
  end
end

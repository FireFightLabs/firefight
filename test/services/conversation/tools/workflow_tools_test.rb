require "test_helper"

# Halon makes, runs and lists workflows from a chat: each confirmed on the card first, made as Halon's draft, published
# with its grants by someone who may, and otherwise a draft an admin is asked to publish.
class Conversation::Tools::WorkflowToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    Conversation::Plans.stubs(:time_zone_of).returns("Europe/Belgrade")
    @adapter = WorkspaceAdapter.for(@workspace).class
    @adapter.any_instance.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
  end

  def turn(asker, conversation = Conversation.start_personal!(workspace: @workspace, member: asker)) = Conversation::Turn.new(conversation, asker: asker)

  def check_later(minutes: 30) = { template: "check_later", params: { resource: "web", in_minutes: minutes, reply_in_chat: true } }

  test "the tools are offered only where the workspace has workflows" do
    names = ->(asker) { Conversation::Tools.for(turn(asker), offer: ->(_tools) { }).map(&:name) }
    assert_includes names.call(@admin), Conversation::Tools::CreateWorkflow::NAME

    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    assert_not_includes names.call(@admin), Conversation::Tools::CreateWorkflow::NAME
    assert_not_includes names.call(@admin), Conversation::Tools::RunWorkflow::NAME
    assert_not_includes names.call(@admin), Conversation::Tools::ListWorkflows::NAME
  end

  test "making one waits for the person, who is shown when it runs, each step and what it will be able to do" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
      tool = Conversation::Tools::CreateWorkflow.new(turn(@member, conversation))
      call = RubyLLM::ToolCall.new(id: "call_1", name: Conversation::Tools::CreateWorkflow::NAME, arguments: check_later.deep_stringify_keys)
      conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => call }))

      assert tool.requires_approval?
      assert_nil tool.approval_resolver.call(call)
      asked = Chat::Tools.confirmation(conversation.chat.tool_calls.find_by!(tool_call_id: "call_1")).asked
      assert_includes asked, [ "Runs", "Once at #{Chat::TimeToken.for(Time.zone.parse('2026-10-13 12:30 UTC'))}" ]
      assert_includes asked, [ "Ask Halon", "judge: Is web healthy now, and are its error rate and latency within its normal?" ]
      assert(asked.any? { |label, words| label == "It will be able to" && words.include?("post to a channel") })
    end
  end

  test "an admin's confirmed one off is made from the chat, published with its grants and runs as its own identity" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
      said = Conversation::Tools::CreateWorkflow.new(turn(@admin, conversation)).call(**check_later)

      workflow = @workspace.workflows.find_by!(name: "Check web")
      assert_match "Made and published Check web.", said
      assert workflow.live?
      assert_equal conversation, workflow.origin_conversation
      assert workflow.edits.all?(&:by_halon?)
      assert_equal Time.zone.parse("2026-10-13 12:30 UTC"), workflow.next_run_at
      assert_includes workflow.agent.ability_grants.map { |grant| grant.action&.key }, Ability::Action::CHANNEL_POST
    end
  end

  test "publishing held for an approval leaves the draft made, and Halon says so rather than that it could not be made" do
    PolicyRule::ApprovalConditions.stubs(:errors_for).returns([])
    AbilityGateway.stubs(:approval_requirement).returns(nil)
    AbilityGateway.stubs(:approval_requirement).with { |*given| given[2] == Workflow::PUBLISH_KEY }.returns({ "role" => "admin", "count" => 1 })

    said = Conversation::Tools::CreateWorkflow.new(turn(@admin)).call(**check_later)

    workflow = @workspace.workflows.find_by!(name: "Check web")
    assert_not workflow.live?
    assert_equal "Made Check web as a draft. Publishing it is held for an approval, so it waits as a draft and is published once an admin approves.", said.split(" Its card").first
    assert_no_match "not allowed", said
  end

  # Publishing held by a rule an admin decides, whoever asked.
  def hold_publishing
    PolicyRule::ApprovalConditions.stubs(:errors_for).returns([])
    AbilityGateway.stubs(:approval_requirement).returns(nil)
    AbilityGateway.stubs(:approval_requirement).with { |*given| given[2] == Workflow::PUBLISH_KEY }.returns({ "role" => "admin", "count" => 1 })
    Ability::Approval.any_instance.stubs(:self_approvable?).returns(true)
  end

  test "publishing held for an approval happens once an admin approves, exactly the draft that was asked about" do
    hold_publishing
    Conversation::Tools::CreateWorkflow.new(turn(@admin)).call(**check_later)
    workflow = @workspace.workflows.find_by!(name: "Check web")
    approval = Ability::Approval.find_by!(action_key: Workflow::PUBLISH_KEY, status: Ability::Approval::STATUS_PENDING)
    asked = workflow.draft.revision

    perform_enqueued_jobs { approval.approve!(by: @admin) }

    workflow.reload
    assert workflow.live?
    assert_equal asked, workflow.live_version.revision
    assert approval.reload.consumed_at
    assert_includes workflow.agent.ability_grants.map { |grant| grant.action&.key }, Ability::Action::CHANNEL_POST
  end

  test "an approval for publishing a draft changed since it was asked is refused with why" do
    hold_publishing
    Conversation::Tools::CreateWorkflow.new(turn(@admin)).call(**check_later)
    workflow = @workspace.workflows.find_by!(name: "Check web")
    approval = Ability::Approval.find_by!(action_key: Workflow::PUBLISH_KEY, status: Ability::Approval::STATUS_PENDING)
    workflow.edit!(operation: Workflow::Edit::OPERATION_RENAME, payload: { step_id: "step_tell", name: "say_it" }, by: @admin)

    error = assert_raises(Ability::Approval::NotAllowed) { approval.approve!(by: @admin) }

    assert_equal "Check web changed since Alice Smith asked, so open it and look again before publishing.", error.message
    assert approval.reload.pending?
    assert_not workflow.reload.live?
  end

  test "a member's confirmed workflow is a draft and the admins are asked to publish it" do
    said = Conversation::Tools::CreateWorkflow.new(turn(@member)).call(**check_later)

    workflow = @workspace.workflows.find_by!(name: "Check web")
    assert_match "Made Check web as a draft.", said
    assert_match "to publish Check web.", said
    refute workflow.live?
    assert workflow.publish_requests.waiting.exists?(requester: @member)
  end

  test "a workflow that could not be published is not made, and Halon hears what to fix" do
    tool = Conversation::Tools::CreateWorkflow.new(turn(@admin))

    said = tool.call(name: "Broken", steps: [ { name: "look", kind: "call_tool", config: { tool: "no_such_tool" } } ])

    assert_match "look calls no_such_tool, which is not a tool in this workspace.", said
    assert_not @workspace.workflows.exists?(name: "Broken")
  end

  test "a later time asked of make_plan is a workflow here" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    conversation.chat_record
    tool = Conversation::Tools::MakePlan.new(turn(@admin, conversation))

    said = tool.call(goal: "restart web", steps: [ { description: "Restart web", kind: "change", undo: "Nothing" }, { description: "Check", kind: "check" } ],
                     run_at: "2026-10-14T02:00")

    assert_match Conversation::Tools::MakePlan::LATER_IS_A_WORKFLOW, said.to_s
  end

  test "running one by name is confirmed with its steps and inputs, then starts as the workflow" do
    workflow = Workflow::Authoring.create!(workspace: @workspace, by: @admin, spec: {
      name: "Release Firefight", trigger: { kind: "manual", inputs: [ { key: "bump", question: "Which bump?", default: "patch" } ] },
      steps: [ { name: "look", kind: "call_tool", config: { tool: Mcp::Tools::SEARCH_INCIDENTS, arguments: { query: "release {{inputs.bump}}" } } } ]
    })
    workflow.update!(aliases: [ "ship it" ])
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @admin)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    tool = Conversation::Tools::RunWorkflow.new(turn(@member, conversation))
    call = RubyLLM::ToolCall.new(id: "call_2", name: Conversation::Tools::RunWorkflow::NAME, arguments: { "workflow" => "ship it", "inputs" => { "bump" => "minor" } })
    conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_2" => call }))

    asked = Chat::Tools.confirmation(conversation.chat.tool_calls.find_by!(tool_call_id: "call_2")).asked
    assert_includes asked, [ "Input bump", "minor" ]
    said = nil
    perform_enqueued_jobs { said = tool.call(workflow: "ship it", inputs: { bump: "minor" }) }

    run = workflow.runs.sole
    assert_match "Started Release Firefight.", said
    assert_equal Workflow::Run::STARTED_BY_HALON, run.started_by_kind
    assert_equal @member, run.started_by
    assert_equal workflow.agent, run.agent
    assert_match "No workflow is called deploy everything", tool.call(workflow: "deploy everything")
  end

  test "listing names each workflow with what starts it and the inputs a run asks" do
    Conversation::Tools::CreateWorkflow.new(turn(@admin)).call(**check_later)

    listed = JSON.parse(Conversation::Tools::ListWorkflows.new(turn(@member)).call)

    assert_equal [ "Check web" ], listed.map { |row| row["name"] }
    assert_match "Once on", listed.first["starts"]
  end
end

require "test_helper"

# A workflow Halon made in a chat: its card there with Run now and Cancel, each saying it happened, the same from the
# message in a Slack thread, and nothing of it without the workflows flag.
class AgentChatWorkflowsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:unavailable_reason).returns(nil)
    ConversationChannel.stubs(:broadcast_to)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @conversation.chat_record
    travel_to Time.zone.parse("2026-10-13 12:00 UTC")
    @workflow = Workflow::Authoring.create!(workspace: @workspace, by: @bob, halon: true, reason: "Bob asked for it.", origin_conversation: @conversation,
                                            spec: { template: "check_later", params: { resource: "web", in_minutes: 30, reply_in_chat: true } })
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @alice)
    sign_in(users(:bob), @workspace)
  end

  teardown { travel_back }

  test "the chat shows the card with Run now and Cancel, which whoever made it may press" do
    get agent_chat_path(@conversation), headers: inertia_headers

    card = inertia_props["workflows"].sole
    assert_equal [ "Check web", true, "2026-10-13T12:30:00Z" ], card.values_at("name", "oneOff", "nextRunAt")
    assert_equal [ [ "run_now", nil ], [ "cancel", nil ] ], card["offers"].map { |offer| offer.values_at("action", "blockedReason") }
  end

  test "Run now starts a run and Cancel stops it running on its own, each saying so" do
    Workflow::Run.any_instance.stubs(:may_move?).returns(false)
    post agent_chat_workflow_press_path(@conversation, @workflow, Workflow::ACTION_RUN_NOW)
    assert_equal "Check web is running.", flash[:notice]
    assert_equal 1, @workflow.runs.count

    post agent_chat_workflow_press_path(@conversation, @workflow, Workflow::ACTION_CANCEL)
    assert_equal "Check web was cancelled. It will not run.", flash[:notice]
    assert_not @workflow.reload.enabled?
    assert_nil @workflow.next_run_at
  end

  test "someone else is refused Cancel with why" do
    other = workspace_memberships(:alice_workspace_one)
    assert_nil @workflow.stop_blocked_reason(other)

    member = @workspace.workspace_memberships.create!(user: users(:charlie), role: :member, joined_at: Time.current)
    assert_equal "Only #{@bob.display_name} or a workspace admin can stop Check web.", @workflow.stop_blocked_reason(member)
  end

  test "without the flag the chat shows no workflow card" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    get agent_chat_path(@conversation), headers: inertia_headers

    assert_empty inertia_props["workflows"]
  end

  test "Cancel pressed on the message in the thread works the same and a refusal is said privately" do
    adapter = WorkspaceAdapter.for(@workspace)
    @workspace.stubs(:adapter).returns(adapter)
    member = @workspace.workspace_memberships.create!(user: users(:charlie), role: :member, platform_user_id: "U0CHARLIE", joined_at: Time.current)
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, workspace: @workspace, user_id: member.platform_user_id,
                                  action_id: Identifiers::CHAT_WORKFLOW_STOP, action_value: @workflow.id, channel_id: "C1")
    adapter.expects(:post_ephemeral).with(channel_id: "C1", user_id: "U0CHARLIE", text: "Only #{@bob.display_name} or a workspace admin can stop Check web.")

    Interactions::ChatWorkflowHandler.execute(interaction)
    assert @workflow.reload.enabled?

    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, workspace: @workspace, user_id: @bob.platform_user_id,
                                  action_id: Identifiers::CHAT_WORKFLOW_STOP, action_value: @workflow.id, channel_id: "C1")
    Interactions::ChatWorkflowHandler.execute(interaction)
    assert_not @workflow.reload.enabled?
  end

  test "a workflow made in a thread keeps a message there with Run now and Cancel, redrawn as it moves" do
    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "111.1")
    adapter = WorkspaceAdapter.for(@workspace).class
    adapter.any_instance.expects(:post_chat_workflow).with(has_entries(channel_id: "C1", thread_id: "111.1", workflow: @workflow)).returns({ channel_id: "C1", message_id: "222.2" })

    perform_enqueued_jobs { Conversation::Workflows.moved!(@workflow) }
    assert_equal [ "C1", "222.2" ], @workflow.reload.values_at(:chat_message_channel_id, :chat_message_id)

    adapter.any_instance.expects(:update_chat_workflow).with(has_entries(channel_id: "C1", message_id: "222.2"))
    perform_enqueued_jobs { Conversation::Workflows.moved!(@workflow) }

    blocks = Slack::Messages::ChatWorkflow.build(@workflow)
    actions = blocks.find { |block| block[:type] == "actions" }[:elements].filter_map { |element| element[:action_id] }
    assert_equal [ Identifiers::CHAT_WORKFLOW_RUN_NOW, Identifiers::CHAT_WORKFLOW_STOP ], actions
  end
end

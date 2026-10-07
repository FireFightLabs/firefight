require "test_helper"

# A call an approval rule held in a chat. Approving it unlocks it and never runs it: Halon reads how things stand now, the
# person who asked is told where the chat lives, and it runs once, when someone presses Run.
class Conversation::HeldCallsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @faylee = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Faylee", slug: "faylee",
                                              settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    @faylee.integration_environments.create!
    @tool = @faylee.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: @tool.ability_action)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @conversation.chat_record
    @adapter = stub(post_held_call_to_user: { channel_id: "D1", message_id: "9.1" }, post_held_call: { channel_id: "C1", message_id: "9.2" },
                    update_held_call: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "a call held for someone else's approval is kept with the chat, and Halon is told not to try it again" do
    said = hold_call

    held = @conversation.chat.held_calls.sole
    assert_equal [ Chat::HeldCall::STATUS_WAITING, "faylee_execute", @faylee.target_label ], [ held.status, held.tool_name, held.target ]
    assert held.approval.held_for_run?
    assert_equal({ "kind" => Chat::HeldCall::RESUME_KIND, "held_call_id" => held.id }, held.approval.resume_payload)
    assert_match "never call it again yourself", said
  end

  test "approving it only unlocks it: nothing runs, Halon is asked to check, and the person who asked is told in Slack" do
    Integrations::McpExecutor.expects(:call).never
    hold_call
    held = @conversation.chat.held_calls.sole
    @adapter.expects(:post_held_call_to_user).with do |user_id:, held_call:|
      user_id == @bob.platform_user_id && held_call.headline == "Alice Smith approved: Execute on #{@faylee.target_label}. Run it now?"
    end.returns(channel_id: "D1", message_id: "9.1")

    perform_enqueued_jobs(only: AbilityApprovalResumptionJob) { held.approval.approve!(by: @alice) }

    assert_equal Chat::HeldCall::STATUS_CHECKING, held.reload.status
    assert_equal [ "D1", "9.1" ], [ held.message_channel_id, held.message_id ]
    assert_enqueued_with(job: HeldCallCheckJob, args: [ held.id ])
    assert_enqueued_with(job: ApprovedCallExpiryJob, args: [ held.approval.id ])
    assert_in_delta 1.hour.from_now, held.approval.run_expires_at, 5.seconds
    assert_not Ability::Invocation.exists?(approval_id: held.approval.id, decision: Ability::Invocation::DECISION_ALLOW)
    assert_equal "Halon is still checking how things stand now.", held.run_blocked_reason(@bob)
  end

  test "Halon reads how things stand now before Run is offered, and the card says plainly when it looks done already" do
    held = approved_call
    Chat::StateCheck.expects(:run).with do |owner:, principal:, call:, **|
      owner == held && principal == @bob && call.named == "Execute on #{@faylee.target_label}"
    end.returns(Chat::CurrentState::Report.new(state: "web already runs 0 instances.", change: Chat::CurrentState::DONE_ALREADY))
    @adapter.expects(:update_held_call).with { |message_id:, held_call:, direct:, **| message_id == "9.1" && direct && held_call.status == Chat::HeldCall::STATUS_READY }

    Conversation::HeldCalls.check!(held)

    shown = Conversation::HeldCalls.shown(held.reload)
    assert_equal [ Chat::HeldCall::STATUS_READY, "web already runs 0 instances.", "This looks done already." ], [ shown.status, shown.state, shown.warning ]
    assert_equal [ Chat::CurrentState::ACTION_RUN, Chat::CurrentState::ACTION_DISMISS ], shown.offers
    assert_nil held.run_blocked_reason(@bob)
  end

  test "a check that cannot read anything still unlocks Run, and says nobody checked" do
    held = approved_call
    Investigation.stubs(:unavailable_reason).returns("Investigations are not turned on for this workspace.")

    perform_enqueued_jobs(only: HeldCallCheckJob) { HeldCallCheckJob.perform_later(held.id) }

    assert_equal [ Chat::HeldCall::STATUS_READY, Chat::CurrentState::UNKNOWN ], [ held.reload.status, held.state_change ]
    assert_equal Chat::CurrentState::WORDS[Chat::CurrentState::UNKNOWN], Conversation::HeldCalls.shown(held).warning
  end

  test "Run runs it once, through the gateway with its approval, as whoever asked, and Halon is told what it said" do
    held = ready_call
    Integrations::McpExecutor.expects(:call).once.returns("content" => [ { "type" => "text", "text" => "Scaled web to 0" } ])

    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @bob.id, held.id ]) do
      assert_nil Conversation::HeldCalls.run!(held, by: @bob)
    end
    assert_equal "This is no longer waiting to be run.", Conversation::HeldCalls.run!(held.reload, by: @bob)
    assert @conversation.reload.answer_owed?

    chat = @conversation.chat
    Conversation::Runner.new(@conversation, asker: @bob, held_call: held.reload).send(:run_held_call, chat)
    Conversation::Runner.new(@conversation, asker: @bob, held_call: held.reload).send(:run_held_call, chat)

    invocation = Ability::Invocation.find_by!(approval_id: held.approval.id, decision: Ability::Invocation::DECISION_ALLOW)
    assert_equal [ @bob, AbilityGateway::SOURCE_CONVERSATION, Ability::Invocation::OUTCOME_SUCCESS ], [ invocation.principal, invocation.source, invocation.outcome ]
    assert_equal [ Chat::HeldCall::STATUS_RAN, invocation.id, @bob ], [ held.reload.status, held.invocation_id, held.decided_by ]
    assert held.approval.reload.consumed_at
    note = chat.messages.where(nudge: true).sole
    assert_match "Bob Jones ran the approved call Execute on #{@faylee.target_label}", note.content
    assert_match "Scaled web to 0", note.content
    assert held.told_at
  end

  test "someone else in the chat runs it only when they may make the same call, and it still runs as whoever asked" do
    held = ready_call
    carol = @workspace.workspace_memberships.find_by(user: users(:charlie)) || @workspace.workspace_memberships.create!(user: users(:charlie), role: WorkspaceMembership.roles[:member], platform_user_id: "U333", joined_at: Time.current)

    assert_match "Only Bob Jones or someone who may make this call can run it.", held.run_blocked_reason(carol)
    assert_nil held.run_blocked_reason(@alice)
  end

  test "Dismiss means it never runs, and its approval can no longer be used" do
    held = ready_call
    Integrations::McpExecutor.expects(:call).never

    assert_nil Conversation::HeldCalls.dismiss!(held, by: @bob)

    assert_equal [ Chat::HeldCall::STATUS_DISMISSED, @bob ], [ held.reload.status, held.decided_by ]
    assert_equal Ability::Approval::STATUS_DISMISSED, held.approval.reload.status
    assert_not held.approval.usable?
    assert_equal "This is no longer waiting to be run.", Conversation::HeldCalls.run!(held, by: @bob)
    assert_match "dismissed it after it was approved", Conversation::HeldCalls.untold_note(@conversation.chat)
  end

  test "an approval nobody runs within the hour expires, says so, and can be asked for again without running anything" do
    held = ready_call
    Integrations::McpExecutor.expects(:call).never

    travel Ability::Approval::RUN_WINDOW + 1.minute do
      assert_equal Chat::HeldCall::STATUS_EXPIRED, Conversation::HeldCalls.shown(held.reload).status
      assert_equal Chat::HeldCall::EXPIRED, held.run_blocked_reason(@bob)

      perform_enqueued_jobs(only: ApprovedCallExpiryJob) { ApprovedCallExpiryJob.perform_later(held.approval.id) }
      assert_equal [ Chat::HeldCall::STATUS_EXPIRED, Ability::Approval::STATUS_EXPIRED ], [ held.reload.status, held.approval.reload.status ]
      assert_equal [ Chat::CurrentState::ACTION_ASK_AGAIN ], held.offers

      assert_enqueued_with(job: AbilityApprovalNotificationJob) { assert_nil Conversation::HeldCalls.ask_again!(held, by: @bob) }
    end

    renewed = @conversation.chat.held_calls.find_by!(status: Chat::HeldCall::STATUS_WAITING)
    assert_equal Chat::HeldCall::STATUS_ASKED_AGAIN, held.reload.status
    assert renewed.approval.pending?
    assert_equal held.approval.request_digest, renewed.approval.request_digest
    assert_not_equal held.approval_id, renewed.approval_id
  end

  test "a denial tells the person who asked, nothing runs, and Halon hears it once" do
    Integrations::McpExecutor.expects(:call).never
    hold_call
    held = @conversation.chat.held_calls.sole
    @adapter.expects(:post_held_call_to_user).with { |held_call:, **| held_call.headline == "Alice Smith denied: Execute on #{@faylee.target_label}. Nothing ran." }
            .returns(channel_id: "D1", message_id: "9.3")

    perform_enqueued_jobs(only: AbilityApprovalResumptionJob) { held.approval.deny!(by: @alice) }

    assert_equal Chat::HeldCall::STATUS_DENIED, held.reload.status
    assert_match "Alice Smith denied it.", Conversation::HeldCalls.untold_note(@conversation.chat)
    assert_nil Conversation::HeldCalls.untold_note(@conversation.chat)
  end

  test "in a chat that lives in a Slack thread the news is posted in the thread and redrawn there as it moves" do
    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C9", thread_id: "5.5")
    hold_call
    held = @conversation.chat.held_calls.sole
    @adapter.expects(:post_held_call).with { |channel_id:, thread_id:, **| channel_id == "C9" && thread_id == "5.5" }.returns(channel_id: "C9", message_id: "5.6")
    @adapter.expects(:post_held_call_to_user).never

    perform_enqueued_jobs(only: AbilityApprovalResumptionJob) { held.approval.approve!(by: @alice) }
    @adapter.expects(:update_held_call).with { |message_id:, direct:, **| message_id == "5.6" && !direct }
    Conversation::HeldCalls.dismiss!(held.reload, by: @bob)
  end

  test "an outside agent's chat and an investigation keep nothing to run later, as before" do
    mcp_chat = Conversation.for_mcp!(workspace: @workspace, principal: @bob)
    mcp_chat.chat_record
    approval = @workspace.ability_approvals.create!(principal: @bob, principal_label: "Bob", action_key: @tool.action_key, request_digest: "x",
                                                    required_role: "admin")
    run = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 1, max_spend_cents: 1)

    assert_not Conversation::Turn.new(mcp_chat, asker: @bob).hold!(approval, tool_name: "faylee_execute", tool_call_id: "c")
    assert_not run.hold!(approval, tool_name: "faylee_execute", tool_call_id: "c")
    assert_empty Chat::HeldCall.where(approval: approval)
  end

  private

  def hold_call
    Chat::Tools::Connection.new(Conversation::Turn.new(@conversation, asker: @bob), @tool).call(tool_call: stub(id: "call_1"), "code" => "scale web to 0")
  end

  def approved_call
    hold_call
    held = @conversation.chat.held_calls.sole
    perform_enqueued_jobs(only: AbilityApprovalResumptionJob) { held.approval.approve!(by: @alice) }
    held.reload
  end

  def ready_call
    held = approved_call
    held.checked!(Chat::CurrentState::Report.new(state: "web runs 2 instances.", change: Chat::CurrentState::UNCHANGED))
    held
  end
end

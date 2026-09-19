require "test_helper"

# A change the agent is about to make waits for the person, and only their answer lets it through.
class Conversation::ConfirmingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C_INCIDENT", thread_id: "1700000000.000100",
      started_by: @member, max_turns: 10, max_spend_cents: 40
    )
    @chat = @conversation.chat_record
  end

  test "a change that destroys or cannot be undone waits for the person, a reversible one does not" do
    turn = Conversation::Turn.new(@conversation, asker: @member)

    assert turn.confirms?(system_action("permissions.delete"))
    assert_not turn.confirms?(system_action("incidents.update"))
  end

  test "an investigation never waits on anyone" do
    investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 5, max_spend_cents: 40
    )

    assert_not investigation.confirms?(system_action("permissions.delete"))
  end

  test "a question is answered once, however many times it is clicked" do
    ask_about("call_1")

    assert @chat.decide!("call_1", approved: true)
    assert_not @chat.decide!("call_1", approved: false)
    assert_equal Chat::APPROVAL_APPROVED, @chat.tool_calls.find_by!(tool_call_id: "call_1").approval
  end

  test "the turn carries on only once the last open question is answered, as whoever answered it" do
    ask_about("call_1", "call_2")
    other = workspace_memberships(:bob_workspace_one)

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      assert_not Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true } ], by: @member)
    end
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, other.id ]) do
      assert Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_2", approved: false } ], by: other)
    end
  end

  test "a Slack button answers the question and redraws the message with the answer" do
    ask_about("call_1")
    Slack::Client.expects(:update_message).with do |arguments|
      arguments[:ts] == "1700000000.000200" && arguments[:blocks].to_json.include?("Confirmed")
    end.returns({ ok: true })

    Interactions::AgentConfirmationHandler.execute(Interaction.new(
      type: Interaction::BLOCK_ACTIONS, platform: Platforms::SLACK, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, channel_id: "C_INCIDENT", action_id: Identifiers::AGENT_CONFIRM,
      action_value: "#{@conversation.id}:call_1", message_id: "1700000000.000200"
    ))

    assert_equal Chat::APPROVAL_APPROVED, @chat.tool_calls.find_by!(tool_call_id: "call_1").approval
  end

  test "a turn that stops on a question asks it in the thread rather than answering" do
    ask_about("call_1")
    Chat.any_instance.stubs(:to_llm).returns(stub(pending_approvals: [ Struct.new(:id).new("call_1") ]))
    stub_agent_session
    responder = stub(run: FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_WAITING, turns_used: 1, spent_micros: 0))
    FirefightAi::Responder.stubs(:new).returns(responder)
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].to_json.include?(Identifiers::AGENT_CONFIRM)
    end.returns({ ok: true, ts: "1" })

    Conversation::Runner.new(@conversation, asker: @member).run

    assert_empty @conversation.chat.messages.where(role: Chat::Message::ROLE_ASSISTANT, content: Conversation::Runner::NO_ROOM_LEFT)
  end

  private

  def system_action(key) = Ability::Action.lookup(key, @workspace)

  def ask_about(*tool_call_ids)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    tool_call_ids.each do |id|
      message.ruby_llm_tool_calls.create!(tool_call_id: id, name: "delete_permission_set", arguments: { "slug" => "chat_test" })
    end
    @chat.request_decisions!(tool_call_ids)
  end
end

require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @chat = @workspace.chats.create!(owner: @investigation, model: "claude-sonnet-4-5", provider: :anthropic)
  end

  test "a turn with thinking and a tool call reads back as RubyLLM sent it" do
    @chat.add_message(role: :user, content: "Investigate checkout failures")
    @chat.add_message(thinking_turn(tool_call_id: "toolu_1"))
    @chat.add_message(role: :tool, content: '{"sha":"abc123"}', tool_call_id: "toolu_1")

    reply, result = Chat.find(@chat.id).messages.map(&:to_llm).last(2)

    assert_equal "The deploy at 14:02 looks suspicious.", reply.thinking.text
    assert_equal "SIG_ONE", reply.thinking.signature
    assert_equal thinking_blocks, reply.raw_reasoning
    assert_equal [ "toolu_1" ], reply.tool_calls.keys
    assert_equal({ "repo" => "acme/api" }, reply.tool_calls["toolu_1"].arguments)
    assert_equal "toolu_1", result.tool_call_id
    assert_equal '{"sha":"abc123"}', result.content
  end

  test "tool output and reasoning are encrypted at rest" do
    @chat.add_message(thinking_turn(tool_call_id: "toolu_1"))
    @chat.add_message(role: :tool, content: "customer 4411 card declined", tool_call_id: "toolu_1")

    stored = Chat::Message.connection.select_all(
      "SELECT content, thinking_text, thinking_signature, raw_reasoning::text FROM chat_messages WHERE chat_id = $1",
      "stored", [ @chat.id ]
    ).rows.flatten.compact.join(" ")

    assert_no_match "customer 4411", stored
    assert_no_match "deploy at 14:02", stored
    assert_no_match "SIG_ONE", stored
  end

  test "an empty reply left by a killed worker is discarded before resuming" do
    @chat.add_message(role: :user, content: "Investigate checkout failures")
    @chat.add_message(thinking_turn(tool_call_id: "toolu_1"))
    interrupted = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")

    @chat.discard_interrupted_reply!

    assert_not Chat::Message.exists?(interrupted.id)
    assert_equal [ "user", "assistant" ], @chat.messages.pluck(:role)
  end

  test "a reply that carries a tool call is never discarded" do
    @chat.add_message(role: :user, content: "Investigate checkout failures")
    @chat.add_message(thinking_turn(tool_call_id: "toolu_1").merge(content: "", thinking: nil, raw_reasoning: nil))

    @chat.discard_interrupted_reply!

    assert_equal [ "user", "assistant" ], @chat.messages.pluck(:role)
  end

  test "the same tool call id is allowed in another workspace's chat" do
    other_workspace = workspaces(:slack_workspace_two)
    other_investigation = other_workspace.investigations.create!(
      subject: incidents(:active_p0_ws2), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    other_chat = other_workspace.chats.create!(owner: other_investigation, model: "claude-sonnet-4-5", provider: :anthropic)

    @chat.add_message(thinking_turn(tool_call_id: "call_0"))
    other_chat.add_message(thinking_turn(tool_call_id: "call_0"))

    assert_equal 2, RubyLLM::ActiveRecord::ToolCall.where(tool_call_id: "call_0").count
  end

  test "an investigation has one chat" do
    assert_equal @chat, @investigation.reload.chat
    assert_raises(ActiveRecord::RecordNotUnique) do
      @workspace.chats.create!(owner: @investigation, model: "claude-sonnet-4-5", provider: :anthropic)
    end
  end

  private

  def thinking_blocks
    { "anthropic" => [ { "type" => "thinking", "thinking" => "The deploy at 14:02 looks suspicious.", "signature" => "SIG_ONE" } ] }
  end

  def thinking_turn(tool_call_id:)
    {
      role: :assistant, content: "",
      thinking: RubyLLM::Thinking.build(text: "The deploy at 14:02 looks suspicious.", signature: "SIG_ONE"),
      raw_reasoning: thinking_blocks,
      tool_calls: { tool_call_id => RubyLLM::ToolCall.new(id: tool_call_id, name: "list_commits", arguments: { "repo" => "acme/api" }) }
    }
  end
end

require "test_helper"

# What one chat bench scenario cost on Claude Sonnet 5.5 through OpenRouter, call by call, as the ledger recorded it. Nine
# in ten tokens written to the cache were the whole front of the chat written again after open_tools or use_skill changed
# the tool list, which sits first in what is cached. Each write already costs one and a quarter times the input price,
# and an hour's write would cost twice, so nothing is written for an hour.
class FirefightAi::CacheCostTest < ActiveSupport::TestCase
  include FakeProviderHelper

  # input, output, cache read, cache write and what the ledger charged, in millionths of a dollar.
  RECORDED = [
    [ 4, 155, 0, 10_607, 28_076 ], [ 2, 77, 0, 15_264, 38_934 ], [ 2, 223, 15_264, 352, 4_640 ], [ 2, 323, 15_616, 1_586, 8_761 ],
    [ 2, 216, 17_202, 654, 5_519 ], [ 2, 104, 0, 18_788, 48_014 ], [ 2, 362, 18_788, 238, 6_098 ], [ 2, 714, 19_026, 499, 10_294 ]
  ].freeze

  test "the recorded scenario costs what the ledger charged, and the same writes kept for an hour would cost half as much again" do
    default = RECORDED.sum { |input, output, read, written, _| cost("anthropic/claude-sonnet-5.5", "openrouter", input, output, read, written) }
    assert_equal RECORDED.sum(&:last), default
    assert_equal 150_336, default

    direct = RECORDED.sum { |input, output, read, written, _| cost("claude-sonnet-5-5", "anthropic", input, output, read, written) }
    hour = RECORDED.sum { |input, output, read, written, _| cost("claude-sonnet-5-5", "anthropic", input, output, read, written, ttl: "1h") }
    written = RECORDED.sum { |row| row[3] }
    assert_equal 47_988, written
    assert_in_delta written * 1.5, hour - direct, RECORDED.size, "an hour's write is $4 a million against $2.50, on every written token"
  end

  test "no turn of a chat, a run or a check asks for a write that lasts an hour" do
    choice = FirefightAi::ModelChoice.new(model: "anthropic/claude-sonnet-5.5", provider: "openrouter", context: fake_provider_context(openrouter_api_key: "sk-or-test"))
    conversation = Conversation.start_personal!(workspace: workspaces(:slack_workspace_one), member: workspace_memberships(:alice_workspace_one))
    chat = Chat.open!(owner: conversation, workspace: conversation.workspace, model_choice: choice)
    FirefightAi::Responder.new(conversation.workspace, inferable: conversation, model: choice).tap do |responder|
      FirefightAi::AgentLoop.stubs(:new).returns(stub(run: FirefightAi::AgentLoop::Outcome.new(status: :answered, turns_used: 0, spent_micros: 0)))
      chat.add_message(role: :user, content: "What changed?")
      responder.run(chat: chat, tools: [], context: "You are acting for Alice.", budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 10, max_turns: 2))
    end

    assert_not_includes chat.to_llm.render.to_json, "\"ttl\""
    assert(chat.messages.none?(&:cache_ttl))
  end

  private

  def cost(model, provider, input, output, read, written, ttl: nil)
    FirefightAi.cost_micros(model, provider: provider, input: input + read + written, output: output, cache_read: read, cache_write: written,
                                   cache_write_by_ttl: ttl ? { ttl => written } : nil)
  end
end

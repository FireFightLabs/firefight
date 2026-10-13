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

  # The tools the scenario opened later came to about 2,683 tokens. Held from the start, they are written once with the
  # first call and read on every call after, and the two calls that wrote the whole front again after an opening read
  # the front they had and write only what was new.
  OPENED_LATER = 2_683

  test "holding every tool from the start costs the recorded scenario about two fifths less than opening groups" do
    before = RECORDED.sum { |input, output, read, written, _| cost("anthropic/claude-sonnet-5.5", "openrouter", input, output, read, written) }
    after = held(RECORDED, OPENED_LATER).sum { |input, output, read, written| cost("anthropic/claude-sonnet-5.5", "openrouter", input, output, read, written) }

    assert_equal 2, RECORDED.drop(1).count { |row| row[2].zero? }
    assert_operator after, :<, before * 0.65
    assert_equal 90_611, after
  end

  test "the budget holds tools whose definitions fit and refuses those past it, counted in tokens" do
    tool = RubyLLM::Tool.new.tap { |each| each.define_singleton_method(:name) { "read_run" } }
    tool.define_singleton_method(:description) { "x" * 3_400 }
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000)

    assert FirefightAi.fits_up_front?([ tool ])
    assert_not FirefightAi.fits_up_front?([ tool, tool ])
    assert FirefightAi.fits_up_front?([])
  end

  test "a length in characters fits the budget exactly where tools that long in all do" do
    tool = RubyLLM::Tool.new.tap { |each| each.define_singleton_method(:name) { "read_run" } }
    tool.define_singleton_method(:description) { "x" * 3_400 }
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000)
    length = tool.name.size + tool.description.size + tool.parameters_schema.to_json.size

    assert FirefightAi.chars_fit_up_front?(length)
    assert_not FirefightAi.chars_fit_up_front?(length * 2)
    assert FirefightAi.chars_fit_up_front?(3_500)
    assert_not FirefightAi.chars_fit_up_front?(3_501)
    assert FirefightAi.chars_fit_up_front?(0)
  end

  test "the budget defaults to 25,000 tokens, a blank keeps it, zero holds nothing, and anything but a whole number is refused at boot" do
    configuration = FirefightAi::Configuration.new
    assert_equal 25_000, configuration.held_tools_budget
    configuration.held_tools_budget = "40000"
    assert_equal 40_000, configuration.held_tools_budget
    configuration.held_tools_budget = ""
    assert_equal FirefightAi::Configuration::DEFAULT_HELD_TOOLS_BUDGET, configuration.held_tools_budget
    configuration.held_tools_budget = "0"
    assert_equal 0, configuration.held_tools_budget
    assert_raises(ArgumentError) { configuration.held_tools_budget = "25k" }
    assert_raises(ArgumentError) { configuration.held_tools_budget = "-1" }
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

  # The recorded calls as they would have gone with opened tokens of tools held from the start.
  def held(rows, opened)
    front = 0
    rows.each_with_index.map do |(input, output, read, written, _), index|
      read, written = front, written - front if index.positive? && read.zero?
      front = read + written
      index.zero? ? [ input, output, read, written + opened ] : [ input, output, read + opened, written ]
    end
  end

  def cost(model, provider, input, output, read, written, ttl: nil)
    FirefightAi.cost_micros(model, provider: provider, input: input + read + written, output: output, cache_read: read, cache_write: written,
                                   cache_write_by_ttl: ttl ? { ttl => written } : nil)
  end
end
